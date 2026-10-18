# 案例：窗口选项污染（diff / scrollbind 被带到不该有的窗口）

**症状**：插件窗口正常，但用户按 `:`、开 fzf、触发通知后画面错乱（全红、滚动失联、折叠乱套）

## 规则表（需随版本重验）

验证环境：nvim 0.13.0-dev-1617（2026-10-17）。升级后先运行 [probe-win-option.lua](probe-win-option.lua) 对照其预期输出，再信任下表

先理解两个概念（`:help local-options`）：每个窗口有**局部值**，同时还有一份自己的**全局副本**，没有进程级的全局值。新窗口的取值来源是**当前窗口**，与 `nvim_open_win` 的 `win` / `relative` 参数无关

| 场景 | 新窗口的值 |
|------|-----------|
| 新窗口显示**同一 buffer**（`:split`、同 buffer 浮窗） | 复制当前窗口的**局部值**；`style='minimal'` 不清除 `diff` / `scrollbind`（会追加 `winhighlight`） |
| 新窗口显示**新 buffer**（`nvim_open_win(new_buf)`、`:new`） | 取当前窗口的**全局副本**，不取其 `setlocal` 的局部值 |
| 当前窗口 `:set`、`vim.wo.x = v`、不带 scope 的 `nvim_set_option_value` | 同时改局部值和该窗口的全局副本，之后以该窗口为当前窗口开的新窗口会继承 |
| **非当前**窗口 W 上不带 scope 设置 | 同样污染 **W 自己的全局副本**；只有当 W 成为当前窗口后开的新窗口才被传染 |
| `vim.wo[win][0].x`、`scope='local'`（当前或非当前窗口） | 只改局部值，全局副本不变 |

依据：`:help local-options`、`:help vim.wo`、`:help nvim_set_option_value()`。表中每一行都由 probe 脚本复现

## 排查

1. arm `WinNew` / `CmdlineEnter`，dump tab 内所有窗口的 `diff / scrollbind / cursorbind / foldmethod / winhighlight`、filetype，找出不该带这些设置的异物（noice / notify / scrollview / fzf 等）
2. **逐窗口**读全局副本：`nvim_get_option_value('diff', { scope = 'global', win = w })`。不带 `win` 只会读到当前窗口的副本，看不到别的窗口被污染（模板的 dump 示例已包含）
3. 副本为 true 的窗口就是污染源：找到对它不带 scope 设置选项的代码，窗口只是受害者
4. 用探针复现：在对应窗口设选项，再开新 buffer 浮窗，对照上表

## 修复

- **优先从源头**：设置窗口选项时用 `vim.wo[win][0].opt = v` 或 `{ scope = 'local', win = win }`
- **兜底清扫**（污染源是第三方、无法修时）。清扫外来窗口要**不带 scope**，同时清掉局部值和全局副本

```lua
-- state / is_my_window 是占位，按插件实际数据替换
local aug = vim.api.nvim_create_augroup('MyPlugSweepForeign', { clear = true })

local function sweep_foreign(state)
  if not vim.api.nvim_tabpage_is_valid(state.tabpage) then return end

  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(state.tabpage)) do
    if vim.api.nvim_win_is_valid(w) and not is_my_window(state, w) then
      for _, opt in ipairs({ 'diff', 'scrollbind', 'cursorbind' }) do
        if vim.wo[w][opt] then
          -- 不带 scope：带 scope='local' 时，新窗口稍后仍会按全局副本取回污染值
          vim.api.nvim_set_option_value(opt, false, { win = w })
        end
      end
    end
  end
end

-- noice 等用 noautocmd=true 创建窗口不会触发 WinNew，所以 CmdlineEnter 也要挂
for _, ev in ipairs({ 'WinNew', 'CmdlineEnter' }) do
  vim.api.nvim_create_autocmd(ev, {
    group = aug,
    callback = function()
      sweep_foreign(state)
      vim.defer_fn(function() sweep_foreign(state) end, 50)
    end,
  })
end

-- 成对的拆除入口
local function stop_sweep()
  pcall(vim.api.nvim_del_augroup_by_name, 'MyPlugSweepForeign')
end
```

清扫的时序要点：`WinNew` 触发时新窗口里还是旧 buffer，之后 buffer 才设进去并按副本取值，所以只用 `scope='local'` 的同步清扫会被覆盖（实测）；上面不带 scope 的写法同步那次也生效，`defer 50` 用来拦后续异步开 float 的插件。`diff = false` 不等于 `:diffoff`，`foldmethod` 等残留选项需按需单独恢复
