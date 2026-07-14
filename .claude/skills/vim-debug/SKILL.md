---
name: vim-debug
description: 当调试 Neovim 插件（lua / vimscript）的诡异 bug、窗口/buffer 状态异常、第三方插件交互、autocmd 时序、异步回调乱序、或 bug 只在特定短暂瞬间出现（cmdline 打开、模式切换、WinNew 等）难以常规捕获时使用。强调「不凭肉眼、dump 到文件、对比 ground truth」的工程化排查法
---

## 核心原则

1. **不要 `print` / `vim.print` / `:echom`，dump 到 `/tmp/xxx.log` + `pedit`**：cmdline 会被 noice / blink.cmp 浮窗遮挡，`:messages` 里 `\r` / BOM / 零宽字符肉眼透明
2. **`vim.inspect` 而不是 `tostring`**：会把 `"line\r"` / `"\xef\xbb\xbfbom"` / `"zero\u{200b}width"` 显式转义出来
3. **运行时 ≠ 磁盘**：`vim.api.nvim_buf_get_lines` 只是内存视图；`md5sum` / `wc -l` / `od -c` / `git show` 才是 ground truth。任何一项对不上，先怀疑「读入 / 转换」环节
4. **瞬态 bug 用 arm + defer**：bug 只在 `CmdlineEnter` / `WinNew` / `ModeChanged` 一瞬间可见，事件结束就恢复，手动触发抓不到。用 `once=true` autocmd + `vim.defer_fn(200)`（150~300ms 比较稳）等所有同步 + 异步 handler 跑完再 dump
5. **lazy 缓存**：改完 lua 文件不重启 nvim、不 `:Lazy reload`，`require` 不重读。dump 里加**哨兵常量**（每次改代码改字符串），版本号对不上就是缓存

---

## 诊断套件

### dump 命令（写文件 + pedit）

> dump 是快照不是 timeline。每次完整覆盖（`'w'`，不用 `'a'`）；多份对比用 `tag` 分文件名

```lua
local LOG_BASE = '/tmp/myplug-debug'
local function dump(tag)
  local log = (tag and tag ~= '')
      and (LOG_BASE .. '.' .. tag .. '.log') or (LOG_BASE .. '.log')
  local out = {}
  local function add(s) out[#out + 1] = s end
  add('SENTINEL: 2026-04-21-v1')   -- 改代码就改这串，dump 出来对不上 = require 缓存
  add('TS:  ' .. os.date('%Y-%m-%d %H:%M:%S'))
  add('TAG: ' .. (tag or '<none>'))
  add(vim.inspect(require('myplug.state')._state))
  -- 按需追加维度，见下表

  -- 'w' 截断覆盖：dump 是快照不是 timeline，不要 'a' 把多次现场混在一起
  local fh = io.open(log, 'w')
  if fh then fh:write(table.concat(out, '\n')); fh:close() end
  -- pedit 已开着旧 log 的预览窗时，写完会自动 :checktime 刷新，不用手动 reload
  pcall(vim.cmd, 'silent botright pedit ' .. vim.fn.fnameescape(log))
  vim.notify('dumped ' .. log)
end
vim.api.nvim_create_user_command('MyPlugDump',
  function(opts) dump(opts.args) end, { nargs = '?' })
```

按需 dump 的维度：

| 维度 | 抓取方式 |
|------|---------|
| 插件 state | `vim.inspect(M._state)` |
| tab 内所有 win + 关键 win-local 选项 | 遍历 `vim.api.nvim_tabpage_list_wins(tp)`（不要用 `vim.api.nvim_list_wins`，跨 tab 会误伤） |
| buffer 字节级内容 | `vim.api.nvim_buf_get_lines` + `vim.inspect` 每行（暴露 `\r` / BOM / 零宽） |
| buffer 元数据 | `vim.bo[buf]` 的 `filetype / fileformat / fileencoding / bomb / buftype / bufhidden / modified` |
| autocmd 注册列表 | `vim.api.nvim_get_autocmds({ group = 'xxx' })` |
| keymap 注册列表 | `vim.api.nvim_get_keymap('n')` / `vim.api.nvim_buf_get_keymap(buf, 'n')` |
| 当前 mode / 光标 | `vim.api.nvim_get_mode()` / `vim.api.nvim_win_get_cursor(0)` |

### Ground truth 对比（排查编码 / 行尾 / BOM）

```lua
local function shell(cmd)
  local h = io.popen(cmd); if not h then return '<popen fail>' end
  local s = h:read('*a') or ''; h:close(); return (s:gsub('%s+$', ''))
end
add('file     = ' .. shell(('file %q'):format(path)))                -- 编码 / 行尾
add('md5      = ' .. shell(('md5sum < %q'):format(path)))
add('head-hex = ' .. shell(('head -c 16 %q | od -An -c'):format(path)))   -- 抓 BOM
add('git HEAD = ' .. shell(('git -C %q show HEAD:%q | md5sum'):format(root, rel)))
```

### Arm 钩子：捕获瞬态事件 + cmdline 不可用替代

bug 只在事件进行中可见（`CmdlineEnter` / `ModeChanged` / `WinNew`），事件结束就恢复——手动触发抓不到。`once=true` autocmd + `vim.defer_fn(200)` 让所有同步 + 异步 handler 跑完再 dump

```lua
local ARM = 'MyPlugArmDebug'
vim.api.nvim_create_user_command('MyPlugArm', function(opts)
  local args = vim.split(opts.args, '%s+', { trimempty = true })
  local event, tag = args[1] ~= '' and args[1] or 'CmdlineEnter', args[2]
  pcall(vim.api.nvim_del_augroup_by_name, ARM)
  local aug = vim.api.nvim_create_augroup(ARM, { clear = true })
  vim.api.nvim_create_autocmd(event, {
    group = aug, once = true,
    callback = function()
      -- defer_fn(200) 不是 vim.schedule：schedule 排在同 tick 末尾，
      -- 但下一 tick 的 schedule、异步 callback、插件 defer 开的 float 还来不及
      vim.defer_fn(function()
        vim.cmd('MyPlugDump' .. (tag and (' ' .. tag) or ''))
        pcall(vim.api.nvim_del_augroup_by_name, ARM)
      end, 200)
    end,
  })
  vim.notify('armed on ' .. event .. (tag and (' → tag=' .. tag) or ''))
end, { nargs = '*' })
```

如果 `:` 本身就是 bug 触发源（没法再 `:MyPlugDump`），arm 钩子是默认方案；或挂 buf-local Normal 键位：

```lua
vim.keymap.set('n', 'gD', function() vim.cmd('MyPlugDump') end,
  { buffer = buf, silent = true })
```

---

## 多步骤对比排查

dump 的真正威力在「采多份互相对比」。三种模式：

### A. 改前 vs 改后（验证修复）

```vim
:MyPlugArm CmdlineEnter before
:<Enter>
" -- 重启 nvim 加载新代码 --
:MyPlugArm CmdlineEnter after
:<Enter>
```

shell 对比：`diff -u /tmp/myplug-debug.before.log /tmp/myplug-debug.after.log`

### B. 对照变量法（隔离单一变量）—— 找 root cause 的核心步骤

bug 现象出现时，**保持其它条件不变，只换一个变量看 bug 是否消失**。这是科学排查的核心，也是和「改前后」最大的区别——它在改代码之前就告诉你「bug 究竟依赖哪个维度」

例子：

| 隔离的维度 | 对照 tag |
|----------|---------|
| 窗口生命周期 | `reuse-win` / `new-win`（同文件 + 复用窗口 vs 同文件 + 新建窗口） |
| 文件内容 | `file-A` / `file-B`（同窗口路径 + 不同文件） |
| 第三方插件干扰 | `with-noice` / `without-noice` |
| 事件触发路径 | `on-cmdline` / `on-winnew` |

> 跳过这一步就动手 fix，常见结果是「修了 N 个不存在的 bug、放过了真的 root cause」

### C. 多次采样查泄漏

`iter1` / `iter2` / `iter3` 看 state 字段（buf 数量、autocmd 数量）有无单调漂移

**清理**：`rm -f /tmp/myplug-debug*.log`

---

## 常见疑难场景

### A. 异步回调乱序污染 state

**症状**：快速切换 / 连按时，后发起的请求被先返回的回调覆盖

**修复**：单调递增 req_id + 回调前守卫：

```lua
local rid = (M._rid or 0) + 1; M._rid = rid
async(function(result)
  if M._rid ~= rid then cleanup_orphan(result); return end   -- 释放 buf / handle
  commit(result)
end)
```

### B. Buffer 内容和磁盘不一致

**症状**：插件读 file 后渲染和 `cat` 不一样。常见于 markdown / 中文 / Windows 编辑过的文件

**可能原因**：CRLF/LF 混用（`fileformat` 自动识别后 `\r` 被吞/留不一致）、UTF-8 BOM 自动剥（`bomb` 开启）、磁盘已变 buffer 未 `:checktime`、`vim.fn.bufadd` 复用了之前已修改的 buffer、`core.autocrlf` git hook 改 checkout 字节

**排查**：套件 1️⃣ 看 `ff / enc / bomb` → 套件 2️⃣ 对比 md5 / head-hex 定位是「读入」还是「git」环节

### C. autocmd 多插件时序

**症状**：同一事件多个 handler，你的 handler 看不到「应该有的状态」

**关键事实**：
- 同事件多个 autocmd 按 augroup 注册顺序**同步**执行
- `vim.schedule` 推到本 tick 末尾，其它插件也能 schedule
- `vim.defer_fn(ms)` 才是真正延迟，能等异步完成

**修复套路**：同步做一次 + defer 再做一次双保险：

```lua
vim.api.nvim_create_autocmd('CmdlineEnter', {
  callback = function()
    handler()                  -- 拦截前置同步 handler
    vim.defer_fn(handler, 50)  -- 拦截后置同步 + 异步 handler
  end,
})
```

### D. 浮窗/分屏继承不该继承的 win-local 选项

**症状**：插件窗口正常，但用户按 `:` / 开 fzf / 触发通知后画面错乱（全红、滚动失联、折叠乱套）

**根因**：`vim.api.nvim_open_win` / `:split` 创建新窗口时**继承当前 win 的 win-local 选项**，包括 `diff` / `scrollbind` / `cursorbind` / `foldmethod` / `foldexpr` / `winhighlight`。新浮窗被动继承后和你的窗口被纳入同一 diff group（其它选项同理被绑成一组）

**排查**：arm `CmdlineEnter` / `WinNew`，看 tab 所有窗口的 `diff / scrollbind / foldmethod / winhighlight`，找出不该有这些设置的异物（ft 是 noice / notify / scrollview / fzf 等）

**修复模板**（清扫 tab 内非己方窗口的敏感选项）：

```lua
local function sweep_foreign(state)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(state.tabpage)) do
    if vim.api.nvim_win_is_valid(w) and not is_my_window(state, w) then
      for _, opt in ipairs({ 'diff', 'scrollbind', 'cursorbind' }) do
        if vim.wo[w][opt] then
          pcall(vim.api.nvim_set_option_value, opt, false, { win = w })
        end
      end
    end
  end
end
-- WinNew: 常规新窗口都会触发；CmdlineEnter: 补 noice 等用 noautocmd=true 创建窗口绕过 WinNew 的漏网
-- 同步先扫一次 + defer(50) 再扫一次：拦后续异步开 float 的插件（如 cmp / blink.cmp 弹窗）
for _, ev in ipairs({ 'WinNew', 'CmdlineEnter' }) do
  vim.api.nvim_create_autocmd(ev, {
    callback = function()
      sweep_foreign(state)
      vim.defer_fn(function() sweep_foreign(state) end, 50)
    end,
  })
end
```

---

## 反例（禁止）

- ❌ `print` / `vim.print` / `:echom` —— 被 noice / 浮窗挡住
- ❌ 只看 `:messages` —— `\r` / BOM / 零宽字符视觉透明
- ❌ `vim.api.nvim_list_wins()` 判异物 —— 跨所有 tab，会误伤别 tab 的合法窗口；用 `vim.api.nvim_tabpage_list_wins(tp)` 限定到自己的 tab
- ❌ `vim.fn.bufnr('path')` 判 buffer 存在 —— 实际是正则子串匹配，路径有公共前缀就会误命中；用 `vim.fn.bufadd(path)`（exact-match 且幂等，buffer 已存在直接返回 bufnr）
- ❌ `vim.schedule` 一把梭做时序拦截 —— 注册顺序 = 执行顺序，敌对插件 schedule 的东西可能排你后面；该 `vim.defer_fn(ms)` 真延迟就 defer
- ❌ 没拿到 dump 证据就改代码 —— 边猜边改会修一个制造两个
- ❌ 修复后不再 dump 验证 —— 「视觉好像好了」≠ 内部状态真干净
