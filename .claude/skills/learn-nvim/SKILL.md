---
name: learn-nvim
description: 当用户学习 vim 概念时，由用户主动调用
---

## 核心原则

1. **先类比，再补差异**：每个 nvim 概念先给前端/通用工程的对应物，再标出"和前端不同的地方"
2. **只讲用户问的**：用户问 *X 是什么*，不要顺手把整个子系统教一遍
3. **精确标注类比强度**：
   - _完全等价_：window ≈ DOM 容器、autocmd ≈ addEventListener
   - _近似_：vim.schedule ≈ queueMicrotask（语义近，redraw 时机有差）
   - _仅作类比_：diff-group ≈ Monaco DiffEditor（nvim 是**隐式**组，无显式容器）
4. **一句话直接答 + 表格补细节**：避免长段落叙事
5. **避免用 nvim 术语解释 nvim 术语**：见"反例"

---

## 核心术语表

### 对象层

| nvim | 前端类比 | 要点 |
|---|---|---|
| **buffer (buf)** | 虚拟数据模型 / VirtualFile | 一段文本内容。**和显示它的窗口解耦** —— 同一个 buffer 可在多个 window 显示；关窗口不等于删 buffer |
| **window (win)** | DOM 容器 / 组件 slot | 屏幕上显示 buffer 的一块矩形。有 win-local 属性（类似 `element.style`） |
| **tabpage (tab)** | 浏览器工作区 / VSCode Workspace | 一整套窗口布局容器。**不是浏览器 tab**。切 tab 换整套布局。有插件会用"专属 tab"隔离自己的 UI |
| **float window (浮窗)** | `position: fixed/absolute` Modal | `vim.api.nvim_open_win(buf, enter, cfg)` 创建。`cfg.relative` ∈ `'editor' / 'win' / 'cursor'`，有 `zindex / focusable / anchor / noautocmd` |
| **bufnr / winid / tabpage handle** | DOM 节点 id | 整数句柄。对象销毁后 handle 失效，用 `nvim_{buf,win,tabpage}_is_valid(h)` 判活 |
| **buftype** | buffer 的"角色" | `''`（普通文件）/ `'nofile'`（临时）/ `'nowrite'`（只读）/ `'prompt'` 等 |
| **bufhidden** | DOM 移除后数据如何处理 | `'hide'` 保留 / `'wipe'` 销毁 / `'delete'` 卸载 / `'unload'` 卸载保留元信息 |

### 选项层（属性作用域）

| nvim 选项类型 | 前端类比 | 示例 |
|---|---|---|
| **global** | `:root` CSS 变量 | `diffopt` / `scrollopt` / `updatetime` |
| **win-local** | `element.style`（挂 window） | `diff` / `scrollbind` / `cursorbind` / `foldmethod` / `foldexpr` / `foldlevel` / `winhighlight` / `number` |
| **buf-local** | 组件 props（挂 buffer） | `filetype` / `buftype` / `bufhidden` / `modifiable` / `modified` |
| **global-local** | 有全局默认又能 setlocal 覆盖 | `fillchars` / `diffopt` 等少数 |

### 事件层

| nvim | 前端类比 | 触发时机 |
|---|---|---|
| **autocmd** | `addEventListener` | `nvim_create_autocmd(event, { group, pattern, callback, once })` |
| **augroup** | 事件命名空间（整组可清） | `nvim_create_augroup('Name', { clear = true })`，同名再注册清掉旧的，防叠加 |
| **WinNew / WinClosed** | MutationObserver（新/移除 DOM） | 新窗口出现/关闭。**`nvim_open_win({ noautocmd = true })` 不触发** |
| **CmdlineEnter / CmdlineLeave** | input focus / blur | 按 `:` / `/` 进/出命令行 |
| **BufWinEnter / BufWinLeave** | element 进入 / 离开 DOM | 某 buffer 挂到某 window / 从窗口切走 |
| **BufRead / BufWritePost** | fetch 响应 / write 完成 | 读入文件后 / 写磁盘后 |
| **ModeChanged** | 全局模式切换 | `'n:i'` / `'i:n'` 等 pattern |
| **FileType / LspAttach / ColorScheme** | 条件挂钩 | 文件类型确认 / LSP 附着 / 主题切换 |

### 时序层（最容易踩坑）

| API | 前端类比 | 语义 |
|---|---|---|
| 同步回调 | 立即 `fn()` | autocmd callback 默认**同步**执行，nvim 返回前跑完 |
| `vim.schedule(fn)` | `queueMicrotask(fn)` | 推到当前同步栈末尾；**可能在 redraw 之后** |
| `vim.defer_fn(fn, ms)` | `setTimeout(fn, ms)` | 真延迟；等异步 handler + 第三方浮窗落定 |
| `vim.wait(ms, cond)` | 阻塞轮询 | 同步等条件，事件循环仍转，慎用 |

---

## lua 里访问 vim 的命名空间（新手必查）

前端人第一次看 nvim lua 代码常被满屏 `vim.xxx` 搞晕。

| 命名空间 | 作用 | 典型写法 |
|---|---|---|
| `vim.api` | 底层 C API（稳定） | `vim.api.nvim_open_win(...)` / `nvim_create_autocmd(...)` |
| `vim.fn` | Vimscript 函数桥 | `vim.fn.bufadd(path)` / `vim.fn.getcwd()` |
| `vim.cmd` | 执行 ex 命令（命令行那行） | `vim.cmd('vsplit')` / `vim.cmd.tabclose()` |
| `vim.opt` | 选项的"OO 封装" | `vim.opt.number = true` / `vim.opt.diffopt:append('linematch:60')` |
| `vim.o / vim.bo / vim.wo` | 选项的扁平 getter/setter | `vim.o.number = true`（global）/ `vim.bo[buf].filetype = 'lua'`（buffer）/ `vim.wo[win].diff = false`（window） |
| `vim.b / vim.w / vim.t / vim.g` | 用户自定义变量（非选项） | `vim.b[buf].my_flag = true`（buffer 级）/ `vim.g.user_setting = 1`（全局） |
| `vim.keymap` | 按键映射 | `vim.keymap.set('n', 'gD', fn, { buffer = buf, silent = true })` |
| `vim.ui` | 用户交互（select / input） | `vim.ui.select(items, {}, cb)` |
| `vim.lsp / vim.diagnostic / vim.treesitter` | 内置模块 | LSP / 诊断 / Treesitter 语法 |

**`vim.wo[win].x = y` vs `nvim_set_option_value('x', y, { win = win })`**：前者语法糖，同义；选一种用即可。

---

## nvim 的隐式"组"机制

nvim 的几组窗口级联动**没有显式容器**，只靠窗口选项决定成员资格。踩坑根源。

### diff-group

- **机制**：所有 `vim.wo[win].diff == true` 的窗口**自动互相配对**做 xdiff 对比，高亮 `DiffAdd / DiffDelete / DiffChange / DiffText`
- **上限**：**最多 8 个成员**，超过抛 `E96: Cannot diff more than 8 buffers`
- **常见污染源**：新窗口从 current win 继承 `diff=true` → 浮窗空内容和 diff 窗口对比 → 整片 DiffAdd

### scrollbind / cursorbind group

- 同机制：所有 `scrollbind=true` 的窗口同步滚动；`cursorbind=true` 的同步光标
- 不影响 diff 高亮，但同样被 `nvim_open_win` 继承

### "隐式组"带来的思维转变

前端的 DiffEditor 是**显式容器**（`<DiffEditor><Original/><Modified/></DiffEditor>`），加成员要 opt-in；
nvim 反过来：**只要设了选项就自动入组**，摘除才需要 opt-out。防御代码都围绕"怎么阻止窗口被意外加入组"。

---

## win-local 选项继承坑

`nvim_open_win(buf, enter, cfg)` 创建新窗口时，**继承 current win 的 win-local 选项**（`diff / scrollbind / cursorbind / foldmethod / foldexpr / foldlevel / foldenable / winhighlight` 等）。

前端类比（假想 DOM 坑）：

```js
// 假想 API：createFloat 自动复制 document.activeElement 的 className
const float = createFloat({ content: '...' })
// 若 activeElement 有 .diff-editor → float 也自动有 → 被隐式 DiffEditor 吸入
```

**三层防御（可靠性从弱到强）**：

1. **自己的窗口显式清零**
   ```lua
   vim.wo[my_win].diff = false
   ```
   只防"从己方继承"；无法防"第三方浮窗从 current win 继承"

2. **`WinNew` autocmd 同步扫除**（不 `vim.schedule`）
   ```lua
   vim.api.nvim_create_autocmd('WinNew', {
     callback = function()
       local w = vim.api.nvim_get_current_win()
       if is_foreign(w) then vim.wo[w].diff = false end
     end,
   })
   ```
   `vim.schedule` 会延到 redraw 后，污染已落下。且 **`noautocmd = true` 创建的浮窗不触发 WinNew**

3. **Monkey-patch `vim.api.nvim_open_win`**（最可靠）
   拦的是 API 入口，绕不过 `noautocmd`

---

## monkey-patch / install / uninstall

等价前端，生命周期要配对。

```lua
local orig = nil

local function wrapper(...)
  local result = orig(...)
  -- 额外逻辑
  return result
end

---@return boolean installed_now
local function install()
  if orig ~= nil then return false end  -- 幂等：防把自己的 wrapper 当原版存
  orig = vim.api.nvim_open_win
  vim.api.nvim_open_win = wrapper
  return true
end

---@return boolean uninstalled_now
local function uninstall()
  if orig == nil then return false end
  vim.api.nvim_open_win = orig          -- 还原到安装前（可能是别家 wrapper）
  orig = nil
  return true
end
```

**链式兼容**：uninstall 只还原到自己保存的 orig，即便链路上别家也 patch 过，也只负责自己这一层。

**挂载时机**：插件启用时 `install()`，teardown（整个 UI 关闭、`VimLeavePre`、专属 tab `TabClosed`）里 `uninstall()`。**避免 nvim 整个生命周期内都劫持全局 API**。

---

## 常见黑话平替

### `noautocmd = true`

`nvim_open_win(buf, enter, { relative = 'editor', ..., noautocmd = true })` —— **创建时不触发任何 autocmd**（`WinNew / BufWinEnter / WinEnter` 全静默）。

用途：插件想"悄悄"开浮窗不惊动监听器（性能 / 避循环）。
后果：你挂的 `WinNew` 监听对这种浮窗无效，必须改用 API 劫持。

### tab-scoped

_作用域只在某个 tabpage 内部_。常见用法 `nvim_tabpage_list_wins(tp)` 只列某个 tab 的 window，避免 `nvim_list_wins()` 跨 tab 误伤。

### teardown / install / uninstall

等同前端 `useEffect` 的 subscribe / cleanup、`AbortController.abort()`。monkey-patch、autocmd 注册、临时 keymap 都需要配对 teardown，否则重载后累积多份回调。

### sweeper

非正式俗称。指"遍历所有窗口把不该设某选项的窗口批量改掉"的函数。类比前端"扫 DOM 找不合规节点改 class"。

### diffoff / diffoff!

ex 命令。`:diffoff` 关当前窗口的 `diff`；`:diffoff!` 关**当前 tab 所有窗口**的 `diff` + 相关副作用（`scrollbind` / `foldmethod` 等）。

### pcall

`local ok, err = pcall(fn, ...)` = `try { fn(...) } catch (err) {}`。nvim 里对"可能因 handle 失效而抛错"的操作（`nvim_set_option_value`、`nvim_win_close` 等）常包一层 pcall 防崩。

### pattern（autocmd 的）

事件的过滤条件，对应 event 类型：
- 文件类：`pattern = '*.md'` 或 `pattern = 'markdown'`（FileType）
- 模式类：`pattern = 'n:i'`（ModeChanged，normal → insert）
- 通配：`pattern = '*'`（默认）

---

## 典型问答模板

**Q：`WinNew` 是什么？**

> 类比 MutationObserver：nvim 在创建新窗口时触发的事件。用 `nvim_create_autocmd('WinNew', { callback })` 监听。**但要注意**：`nvim_open_win({ noautocmd = true })` 创建的浮窗**不触发** WinNew，这类场景要改用 API 劫持。

**Q：`vim.schedule` 和 `setTimeout` 啥区别？**

> 更接近 `queueMicrotask`：推到当前同步栈末尾，仍在同一 tick。但 nvim 的 **redraw 可能在 schedule callback 之前就跑了**——想"防止某种 UI 污染"时，schedule 里改窗口选项经常救不回来。两个替代：**同步**直接改、或 `vim.defer_fn(fn, ms)` 真延迟。

**Q：`tab-scoped` 是什么意思？**

> "只在某个 tabpage 作用域内生效"。nvim 的 tab 不是浏览器 tab，是窗口布局容器。tab-scoped 常见用法：清扫时用 `nvim_tabpage_list_wins(tp)` 只列本 tab 的 window，不误伤其它 tab。

**Q：`vim.wo[w].diff` 和 `nvim_set_option_value('diff', false, { win = w })` 有啥区别？**

> 一个东西的两种写法：`vim.wo` 是语法糖，底层还是调 `nvim_set_option_value`。赋值场景选 `vim.wo[w].x = y` 简洁；需要 `pcall` 包裹防错时选 `nvim_set_option_value`（它能被 pcall，而 `vim.wo` 赋值不能）。

**Q：buffer 和 window 到底什么关系？**

> buffer 是**数据**（一段文本+元信息），window 是**视图**（显示 buffer 的矩形区域）。同一个 buffer 可以被多个 window 同时显示；关闭 window 不影响 buffer。类比：buffer ≈ React state / VirtualFile，window ≈ 渲染它的组件 slot。

**Q：`bufhidden = 'hide'` vs `'wipe'`？**

> buffer 从最后一个 window 切走时的处理策略：
> - `'hide'`：保留 buffer（类似 `display: none`），切回来内容还在
> - `'wipe'`：立即销毁 buffer（类似 unmount），切回来要重新加载
> - `'delete'` / `'unload'`：介于两者之间，几乎不用

**Q：`autocmd` 和 `keymap` 的区别？**

> autocmd = 事件钩子（时机驱动：buffer 打开、mode 切换、win 创建）；keymap = 按键映射（用户输入驱动）。类比：`addEventListener` vs `onClick`。

---

## 反例（禁止）

- ❌ **用 nvim 术语解释 nvim 术语** —— "autocmd 是 Vim 的自动命令"这种循环定义；必须给前端/通用工程类比
- ❌ **假装类比完全等价** —— `vim.schedule` 和 `queueMicrotask` 有 redraw 时机差异；tab 和浏览器 tab 含义完全不同；明确标注差异
- ❌ **一次性灌全章**—— 用户问一个词，不要把整个 autocmd 系统 / 整个 buffer 生命周期翻译一遍；精准作答 + 链接到术语表
- ❌ **不区分"C API"和"Vimscript 桥"** —— `vim.api.nvim_xxx` 是稳定底层，`vim.fn.xxx` 是 Vimscript 函数桥；前端用户常混用导致找不到文档，需明确指路
- ❌ **给 lua 函数不加 `---@param / ---@return` 注释** —— lua 无类型系统，解释代码时补上参数 shape 让前端用户能秒看懂
