---
name: nvim-debug
description: >-
  排查 Neovim 配置或插件（Lua）里需要运行时证据才能定位的问题：窗口、buffer、选项状态异常，画面错乱或高亮异常，打开 / 切换 / 滚动时卡顿，键位或 autocmd 不生效或触发顺序不对，第三方插件互相干扰，异步回调乱序，只在瞬间出现的状态（打开 cmdline、切换模式、新建窗口时）；或对某个 API 的实际行为拿不准、需要实测确认时使用
  方法是 dump 到文件、对比 ground truth、用最小探针验证、对照单一变量
  不用于有明确报错栈的直接修复、学习概念或普通配置写法
---

## 核心原则

1. **证据落文件，不看 `print` / `:messages`**：dump 到 `/tmp/xxx.log` 再 `pedit`。消息区可能被 noice / blink.cmp 浮窗遮挡或截断，不适合当证据
2. **字节级可见化**：`vim.inspect` 只转义控制字符（`\r` 等），BOM 和零宽字符会原样输出；用 `vim.fn.strtrans(s)` 或 `od -c` 才能看见
3. **运行时 ≠ 磁盘**：`nvim_buf_get_lines` 只是内存视图；文件哈希、`od -c`、`git show` 才是 ground truth。任何一项对不上，先怀疑「读入 / 转换」环节
4. **瞬态 bug 用 arm + defer**：bug 只在 `CmdlineEnter` / `WinNew` / `ModeChanged` 一瞬间可见时，用 `once=true` autocmd + `vim.defer_fn(200)` 等其它 handler 跑完再 dump。defer 是时间窗口不是同步保证，慢的异步回调可能超时，能找到对方插件触发的具体事件或回调时优先用它
5. **模块缓存**：`require` 有 `package.loaded` 缓存，改完 lua 不重启则不会重读。清缓存不会撤销旧模块已注册的 autocmd、keymap 和闭包，最稳是重启。dump 里放**哨兵常量**，且哨兵要放在**被修改的模块**里导出，dump 去读它；版本对不上就是缓存
6. **语义存疑先写探针，不凭记忆**：API 行为、选项继承、autocmd 顺序等会随版本变化，先写最小脚本实测，以输出为证据（见下节）

---

## 探针：用最小实验确认 API 语义

```bash
nvim --headless -u NONE -l /path/to/probe.lua   # 干净环境，排除用户配置与插件干扰
```

- **`-l` 脚本执行完就退出，`defer_fn` / timer / 异步回调不会执行**：脚本末尾要 `vim.wait(ms, function() return false end)` 等待
- `print` 在 headless 下会经过消息显示转义（BOM 显示成 `<feff>`、ESC 显示成 `^[`，但 `\r` 原样输出），要看原始字节时写文件再 `od -c`
- 需要真实按键、cmdline、模式切换时，启动 `nvim --headless --listen /path/to/sock`，再用 `nvim --server /path/to/sock --remote-send` 发送按键，结合 arm 采集
- 探针要做**对照**：同一脚本里只换一个变量（如 `setlocal` 与 `vim.wo`、同 buffer 与新 buffer），不要只测期望成立的一侧
- 文档以 `:help <topic>` 为准；结论写进 dump 或笔记时标注 nvim 版本（`nvim --version`）

---

## 诊断套件

模板见 [references/templates.lua](references/templates.lua)（dump / arm / ground truth，标注了验证过的 nvim 版本）。复制后先用 headless 探针跑通再用，不要假设版本一致

### dump 要求

- 快照不是 timeline：每次完整覆盖写（`'w'`，不用 `'a'`），多份对比用 `tag` 分文件名
- 路径用绝对路径，开头写哨兵、时间戳、tag
- 调试工具不能静默失败：`pcall` 吞掉的错误要写进 dump 或 `vim.notify`，尤其是 `pedit`
- 外部命令用 `vim.system({ ... })` 列表参数，不经 shell；`%q` 是 Lua 字面量转义，不是 shell 转义，路径含 `$` 或反引号会被展开甚至执行

按需追加的维度：

| 维度 | 抓取方式 |
|------|---------|
| 插件 state | `vim.inspect(M._state)` |
| tab 内所有 win + 关键 win-local 选项 | 遍历 `nvim_tabpage_list_wins(tp)`；`nvim_list_wins()` 跨所有 tab，会误伤 |
| buffer 字节级内容 | `nvim_buf_get_lines` + `strtrans` 每行，暴露 `\r` / BOM / 零宽 |
| buffer 元数据 | `vim.bo[buf]` 的 `filetype / fileformat / fileencoding / bomb / buftype / bufhidden / modified` |
| autocmd 注册列表 | `nvim_get_autocmds({ group = 'xxx' })`；group 不存在会直接报错，需要 `pcall` |
| keymap 注册列表 | `nvim_get_keymap('n')` / `nvim_buf_get_keymap(buf, 'n')` |
| 当前 mode / 光标 | `nvim_get_mode()` / `nvim_win_get_cursor(0)` |

### Ground truth 对比（编码 / 行尾 / BOM）

- 文件类型、哈希、头部字节（`od -c` 抓 BOM）、`git show HEAD:path` 逐项对比，定位是「读入」还是「git」环节
- `git show` 输出的是 blob 原始字节，不经 smudge / autocrlf，与工作区不同是正常现象；要对比工作区行为用 `git cat-file --filters HEAD:path`
- 算哈希的外部命令输出必须保留原始字节：`vim.system` 的 `text=true` 会把 `\r\n` 规范成 `\n`，不要 `trim`，也不要把 stderr 拼进去；命令失败（文件不在 HEAD、未跟踪）要报错误，不能对错误信息算哈希
- 是否剥 BOM 取决于最终按哪种编码读入，不要用 `bomb` 选项文档推断；实测（0.13-dev）UTF-8 读入时即使 `'fileencodings'` 不含 `ucs-bom` 也会剥，`latin1` 则保留。用探针确认当前版本

### Arm：捕获瞬态事件

- 流程：`:MyPlugArm <event> <tag>` 挂 `once=true` autocmd，事件触发后 defer 再 dump；事件不来时用 `:MyPlugDisarm` 撤销
- 不能指定 pattern（等同 `*`）；重复 arm 会替换上一次。defer 回调里不要删 augroup，否则会误删 200ms 内新一轮 arm（实测复现），`once=true` 已自动清理
- `:` 本身是触发源时无法再 `:MyPlugDump`，arm 是默认方案，或挂 buf-local Normal 键位

---

## 多步骤对比排查

dump 的真正威力在「采多份互相对比」

### 1. 改前 vs 改后（验证修复）

```vim
:MyPlugArm CmdlineEnter before
:<CR>
" -- 重启 nvim 加载新代码 --
:MyPlugArm CmdlineEnter after
:<CR>
```

```bash
diff -u /tmp/myplug-debug.before.log /tmp/myplug-debug.after.log
```

### 2. 对照变量法（隔离单一变量）

bug 出现时，**保持其它条件不变，只换一个变量看 bug 是否消失**。它在改代码之前就告诉你 bug 依赖哪个维度，是找 root cause 的核心步骤

| 隔离的维度 | 对照 tag |
|----------|---------|
| 窗口生命周期 | `reuse-win` / `new-win` |
| 文件内容 | `file-A` / `file-B` |
| 第三方插件干扰 | `with-noice` / `without-noice` |
| 事件触发路径 | `on-cmdline` / `on-winnew` |

> 跳过这一步就动手 fix，常见结果是「修了 N 个不存在的 bug、放过了真的 root cause」

### 3. 多次采样查泄漏

`iter1` / `iter2` / `iter3` 看 state 字段（buf 数量、autocmd 数量）有无单调漂移

**清理**：采集结束后删除本次生成的 `/tmp/myplug-debug.log` 和 `/tmp/myplug-debug.*.log`（不带 tag 的文件不匹配后一个通配），只删自己的前缀

---

## 常见疑难场景

每个场景只列「症状 → 要 dump 的维度 → 待验证假设」。具体 API 行为以探针和 `:help` 为准

### 异步回调乱序污染 state

- **症状**：快速切换 / 连按时，后发起的请求被先返回的回调覆盖
- **dump**：每次请求的 req_id、回调到达顺序、commit 时的 state
- **常见修法**：单调递增 req_id + 回调前守卫，过期结果要释放 buf / handle

```lua
local rid = (M._rid or 0) + 1; M._rid = rid
async(function(result)
  if M._rid ~= rid then cleanup_orphan(result); return end
  commit(result)
end)
```

### Buffer 内容和磁盘不一致

- **症状**：插件读 file 后渲染和 `cat` 不一样，常见于 markdown / 中文 / Windows 编辑过的文件
- **dump**：`fileformat / fileencoding / bomb` + 字节级对比
- **待验证假设**：CRLF/LF 混用、BOM 剥离、磁盘已变但 buffer 未 `:checktime`、`bufadd` 复用了已修改的 buffer、git 的 autocrlf 配置或 filter 改了 checkout 字节

### autocmd 多插件时序

- **症状**：同一事件多个 handler，你的 handler 看不到「应该有的状态」
- **dump**：`nvim_get_autocmds({ event = 'X' })` 的注册顺序、handler 触发时的 state
- **待验证假设**：同一事件的 autocmd 按每条的**定义顺序**执行，与 augroup 无关；插件重新 source（`clear=true` 重建）会让它的 handler 排到队尾
- **常见修法**：同步做一次 + `defer_fn` 再做一次。defer 是竞态窗口，不是同步原语

### 主线程卡顿（打开 / 切换 / 滚动时卡几秒）

- **先拿完整操作路径**：从哪个文件出发、按了什么、卡在哪一步。同一操作从不同起点出发，已加载的插件和窗口选项可能完全不同（实例：从 tsx 出发 vv-i18n 先污染了 `conceallevel`，从 md 出发则不复现）
- **真实 UI 复现**：行高计算、wrap、conceal、重绘的开销在 headless 下测不到；`normal!` 也不触发 `CursorMoved`。用 tmux 起完整配置的 nvim，`send-keys` 发真实按键。起会话前先 `tmux kill-session -t <name>`，残留同名会话会吞掉按键、混入旧数据
- **卡顿检测**：uv timer 每 5ms 记录间隔，超过阈值即主线程被阻塞，配合 `__mark('label')` 打时间点

```lua
local start, last, log = vim.uv.hrtime(), vim.uv.hrtime(), {}
vim.uv.new_timer():start(5, 5, function()
  local now = vim.uv.hrtime()
  local gap = (now - last) / 1e6
  if gap > 50 then log[#log + 1] = ('stall %5.0fms at %6.0fms'):format(gap, (now - start) / 1e6) end
  last = now
end)
```

- **定位调用方**：`require('jit.p').start('pF25m10', file)` 带调用栈（数字 = 栈深，`m` = 最低占比），扁平模式只能看到热点在 treesitter，看不到是谁触发的；结束 `require('jit.p').stop()`
- **计数 hook 的坑**：decoration provider（treesitter highlighter 的 `_on_*` 等）注册时已拿到函数引用，事后替换模块字段不生效，计数为 0 不代表没调用
- **对照单一变量确认根因**，再改代码；修完按原路径重跑，同时检查修复是否改变了别的场景（局部选项见下节规则表）

已知案例：wrap 窗口 + `conceallevel > 0` + markdown 的 `conceal_lines`，`gg` / `]c` / `zz` / `zv` 等需要算行高的命令会对每行调用 `_on_conceal_line` → `tree:parse({row, row+1})`，43 万字节的 md 卡 4s（0.13.0-dev-1617）

### 窗口选项污染（diff / scrollbind / conceallevel 被带到不该有的窗口）

症状是用户按 `:`、开 fzf、触发通知后画面错乱，或新窗口莫名卡顿（继承了 `conceallevel`）。根因与「不带 scope 设置窗口选项会同时改该窗口的全局副本，新窗口再从当前窗口取值」有关，规则表、排查和修法见 [references/case-win-option-inherit.md](references/case-win-option-inherit.md)，规则表可用 [references/probe-win-option.lua](references/probe-win-option.lua) 重验。排查先逐窗口读全局副本（`scope='global', win=w`），不要先写清扫代码

---

## 反例（禁止）

- 用 `print` / `vim.print` / `:echom` 当证据，或只看 `:messages`
- 没拿到 dump 证据就改代码。边猜边改会修一个制造两个
- 修复后不再 dump 验证。「视觉好像好了」不等于内部状态干净
- 把版本相关的 API 行为当作已知事实写进结论，没有探针或 `:help` 依据
- 用 `vim.fn.bufnr('path')` 判断 buffer 是否存在：它是 file-pattern 部分匹配，路径片段会命中名字包含它的其它 buffer。判断存在用 `vim.fn.bufexists(fullpath)`；`bufadd` 会创建 buffer，只在确实需要拿到 buffer 时才用
- 用 `vim.schedule` 单独做时序拦截：它只是排到队尾，其它插件也能排在你后面
