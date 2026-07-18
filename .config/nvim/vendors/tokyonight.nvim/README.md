# TokyoNight.nvim 自定义主题指南（Pretty Dark 移植）

本项目基于 **[Pretty Dark Theme](https://github.com/beixiyo/vsc-theme)**（`cjl.pretty-dark-theme`）的 VSCode 主题移植到 Neovim，所有配色直接写入 fork 源码以避免运行时二次着色

上游为 [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim)，采用 [Apache-2.0](./LICENSE) 许可证；本目录包含基于上游源码修改的本地 fork

## 架构

- 新增 **`lua/tokyonight/colors/pretty_dark.lua`** — 自包含的独立调色板（不继承 storm）
- 通过 `tokyonight.load({ style = "pretty_dark" })` 启用
- 上游原有的 `storm.lua` / `night.lua` / `moon.lua` / `day.lua` **保持官方原版不动**，便于日后从 upstream 同步
- `groups/` 里的高亮组仍然会对所有 style 生效（因为 tokyonight 的设计如此），但 pretty_dark 调色板里包含了 `type` / `variable` / `property` 等扩展字段，只有 pretty_dark 能正确渲染 —— **切到其它 style 会有部分高亮变灰/缺失，属正常**

## 说明

- **基底**：基于 One Dark Pro 深度美化，更暗、更高对比度
- **语义配色**：围绕「类型绿 / 变量红 / 常量黄 / 关键字紫斜体」做跨语言统一

## 文件作用

| 文件夹/文件 | 作用 |
| --- | --- |
| `lua/tokyonight/colors/pretty_dark.lua` | **本项目的自定义调色板（自包含）** |
| `lua/tokyonight/colors/` | 其它颜色调色板（上游原版：storm/night/moon/day） |
| `lua/tokyonight/groups/` | 核心：高亮组定义 |
| `lua/tokyonight/groups/base.lua` | vim 基础高亮组（Keyword、Constant、Folded 等） |
| `lua/tokyonight/groups/treesitter.lua` | treesitter 语法高亮（@keyword、@constant.builtin） |
| `lua/tokyonight/groups/treesitter-context.lua` | 顶部粘性上下文外观 |
| `lua/tokyonight/groups/bufferline.lua` | 顶部标签页高亮 |
| `lua/tokyonight/groups/semantic_tokens.lua` | LSP semantic tokens 高亮 |
| `lua/tokyonight/groups/kinds.lua` | LSP 符号类型（补全菜单中的图标映射） |
| `colors/tokyonight-*.lua` | **`:colorscheme` 入口** — `require("tokyonight").load({style="..."})` 一行，让 `:colorscheme tokyonight-pretty_cat` 这类命令能找到主题 |
| `extras/` | 生成的 Vim colorscheme 导出产物（当前仅 `extras/vim/colors/` 下的 `.vim`） |

## 需要修改的核心文件

| 文件 | 作用 |
|------|------|
| `lua/tokyonight/colors/pretty_dark.lua` | **本主题专属调色板，改色就改这里** |
| `lua/tokyonight/groups/base.lua` | vim 基础高亮组 |
| `lua/tokyonight/groups/treesitter.lua` | treesitter 语法高亮 |
| `lua/tokyonight/groups/semantic_tokens.lua` | LSP semantic tokens |

## 主题设计（与 Pretty Dark VSCode 保持一致）

### 整体风格

| 元素 | 色值 |
|------|------|
| 编辑器背景 | `#191815d6` |
| 工作区前景（文字） | `#c2c2c2` |
| 行高亮背景 | `#23262ced` |
| 选区背景 | `#67769660` |
| 当前行号 | `#c2c2c2` |
| 普通行号 | `#495162` |

### 标签页 / 导航

| 元素 | 色值 |
|------|------|
| 活动标签背景 | `#193d4c` |
| 活动标签前景 | `#c2c2c2` |
| 非活动标签背景 | `#181818` |
| 非活动标签前景 | `#909090` |
| 侧边栏背景 | `#181818` |
| 侧边栏前景 | `#c2c2c2` |

### 语法配色（语义规则）

| 语义 | 颜色 | 色值 | 样式 |
|------|------|------|------|
| 关键字（`if` / `for` / `public` / `class` 等） | 紫色 | `#c678dd` | **斜体** |
| 类型 / 类 / 接口（含 Go / Java / C# 内置类型） | 类型绿 | `#4ec9b0` | |
| 变量（局部变量 / 参数 / 普通字段使用） | 变量红 | `#e06c75` | |
| 结构体 / 对象字段（TS/TSX/Go/Rust 等） | 属性黄橙 | `#d19a66` | |
| 常量 / 枚举 / 只读变量 | 常量黄 | `#e5c07b` | |
| 字符串 | 字符串绿 | `#98c379` | |
| 数字 / 通用常量 | 暖黄橙 | `#d19a66` | |
| 逻辑 / 算术 / 位运算符 | 青色 | `#56b6c2` | |
| 函数 / 方法名 | 函数蓝 | `#61afef` | |
| 命名空间 / 模块 / 包名 | 黄色 | `#e5c07b` | 部分斜体 |
| `this` / `self` / Rust `self` 等内置变量 | 黄色 | `#e5c07b` | |
| 注释 | 暗淡肤黄 | `#ffc3bab7`（不支持透明度时用 `#be938b`） | |

### HTML / CSS / JSX / TSX

| 元素 | 颜色 | 色值 |
|------|------|------|
| 标签名（TSX 纯文本上下文则为中性白 `#c2c2c2`） | 浅蓝 | `#7d99db` |
| 属性名（`className` / `style` 等） | 属性黄橙 | `#d19a66` |
| 尖括号 `< >` | 中性灰 | `#c2c2c2` |
| HTML 内嵌 `<script>` 中的变量 | 中性白 | `#c2c2c2` |
| CSS 属性名 | 中性白 | `#c2c2c2` |

### Markdown

| 元素 | 颜色 | 色值 | 样式 |
|------|------|------|------|
| 标题 | 红系 | `#e06c75` | |
| 有序 / 无序列表符号 | 浅蓝 | `#6f9bff` | |
| 引用块 | 中灰 | `#696969` | |
| 加粗 | 属性黄橙 | `#d19a66` | 加粗 |
| 斜体 | 标签浅蓝 | `#6f9bff` | 斜体 |
| 行内代码 / 代码块 | 字符串绿 | `#98c379` | |
| 链接文字 / URL | 链接蓝 | `#61afef` | |

### Diff / Git

#### Diff 编辑器（并排 / 内联对比）

| 元素 | 色值 |
|------|------|
| 新增文本背景（词级高亮） | `#85e73422` |
| 删除文本背景（词级高亮） | `#ed344322` |
| 新增整行背景 | `#8cc26521` |
| 删除整行背景 | `#50101555` |
| 新增行左侧边栏 | `#233c0eca` |
| 删除行左侧边栏 | `#d8374523` |

#### 装订线 / Minimap（未提交改动标记）

| 元素 | 色值 |
|------|------|
| 新增行标记 | `#109868` |
| 删除行标记 | `#9A353D` |
| 修改行标记 | `#948B60` |

#### 资源管理器 Git 装饰

| 元素 | 色值 |
|------|------|
| 忽略文件前景 | `#636b78` |

### 终端

| 元素 | 色值 |
|------|------|
| 终端背景 | `#181714` |
| 终端前景 | `#c2c2c2` |
| ANSI 蓝 | `#4aa5f0` |
| ANSI 青 | `#42b3c2` |
| ANSI 绿 | `#8cc265` |
| ANSI 红 | `#e05561` |
| ANSI 黄 | `#d18f52` |

## 如何自定义颜色

### 方法一：直接修改源码（推荐）

为了获得最佳性能，建议直接修改源码文件：

1. **修改基础颜色**：编辑 `lua/tokyonight/colors/storm.lua`
   ```lua
   bg = "#你的背景色",
   blue = "#你的函数颜色",
   magenta = "#你的关键字颜色",
   green = "#你的字符串颜色",
   orange = "#你的常量颜色",
   -- 自定义扩展
   type = "#你的类型颜色",
   property = "#你的属性颜色",
   variable = "#你的变量颜色",
   ```

2. **修改语法高亮**：编辑 `lua/tokyonight/groups/treesitter.lua`
   ```lua
   ["@function"] = "Function",
   ["@keyword"] = { fg = c.magenta, style = opts.styles.keywords },
   ["@string"] = "String",
   ["@variable"] = { fg = c.variable, style = opts.styles.variables },
   ["@type"] = { fg = c.type },
   ```

3. **修改基础高亮**：编辑 `lua/tokyonight/groups/base.lua`
   ```lua
   Function = { fg = c.blue, style = opts.styles.functions },
   Keyword = { fg = c.magenta, style = opts.styles.keywords },
   String = { fg = c.green },
   Type = { fg = c.type },
   ```

### 方法二：使用配置覆盖（不推荐）

**注意**：此方法会导致代码二次着色，首次渲染很慢，仅建议用于临时测试

```lua
tokyonight.load({
  style = "night",
  on_colors = function(colors) colors.bg = "#xxx" end,
  on_highlights = function(hl, colors) hl["@function"] = { fg = "#xxx" } end,
})
```

## 性能优化建议

1. **避免使用 `on_colors` 和 `on_highlights`**：这些函数会在运行时重新计算颜色
2. **直接修改源码**：可获得与原生主题相同的渲染速度
3. **减少颜色覆盖**：只修改必要的颜色，保持整体一致性

## 调色板变量速查

| 变量 | 色值 | 用途 |
|------|------|------|
| `c.blue` | `#4aa5f0` | 函数 / 方法名 |
| `c.magenta` | `#c678dd` | 关键字（斜体） |
| `c.green` | `#98c379` | 字符串 |
| `c.orange` | `#d19a66` | 数字 / 布尔 / 属性 |
| `c.constant` | `#e4bf7b` | 常量 / 枚举 / `const` 声明 |
| `c.variable` | `#e06c75` | 变量 / 参数 |
| `c.type` | `#4ec9b0` | 类型 / 类 / 接口 |
| `c.property` | `#d19a66` | 对象属性 |
| `c.operator` | `#c2c2c2` | 运算符 |
| `c.comment` | `#7f848e` | 注释 |

## 调试高亮

在 Neovim 中将光标放到目标 token 上，输入 `:Inspect`，可查看：

- **TreeSitter capture**（如 `@tag.builtin.tsx`、`@variable.tsx`）
- **LSP semantic token**（如 `@lsp.type.class`）
- **链接关系**（最终指向哪个高亮组）

根据输出的 capture name 到对应文件中修改颜色即可

## 重启应用

修改源码后，需要清除缓存并重启 Neovim 才能看到效果：

```bash
rm -rf ~/.cache/nvim/tokyonight*
```

修改配置文件（非源码）后，可用 `:colorscheme tokyonight` 命令重新加载

缓存路径定义在 `lua/tokyonight/util.lua:143`：

```lua
function M.cache.file(key)
  return vim.fn.stdpath("cache") .. "/tokyonight-" .. key .. ".json"
end
```

## Extras 生成机制

`extras/` 下的文件是**生成产物**，不是手写的。本 fork 只在 `M.extras` 里注册了 **vim** 一个 exporter，所以当前只会生成 `extras/vim/colors/` 下的 Vim colorscheme（`.vim`），并没有 kitty / ghostty / alacritty / tmux 等其它工具的导出

- **源头**：`lua/tokyonight/colors/*.lua`（调色板） + `lua/tokyonight/groups/*.lua`（高亮组）
- **生成器**：`lua/tokyonight/extra/init.lua` 的 `M.setup()`
- **exporter 列表**：`extra/init.lua:7-9` 的 `M.extras`，当前只有 `vim = { ..., subdir = "colors", sep = "-" }` 一项
- **style 列表**：`extra/init.lua:16-20` 的 `styles`，当前为 `moon / pretty_moon / pretty_cat`
- **实际产物**：exporter × style，即 `extras/vim/colors/tokyonight-{moon,pretty_moon,pretty_cat}.vim` 三个文件
- **生成命令**（在 fork 根目录执行）：

  ```bash
  nvim --headless +"lua require('tokyonight.extra')" +qa
  ```

### ⚠️ pretty_dark 未加入生成列表

`extra/init.lua:16-20` 的 `styles` 表里硬编码了 `moon / pretty_moon / pretty_cat`，**不含 `pretty_dark`**。这意味着：

- ✅ **Neovim** 使用 pretty_dark 无需任何生成步骤（走 `colors/tokyonight-pretty_dark.lua` 的 lua 加载路径）
- ❌ **经典 Vim（非 nvim）** 当前**无法**使用 pretty_dark，因为 `extras/vim/colors/` 下没有对应的 `.vim` 文件

若需要在经典 Vim 里启用 pretty_dark：

1. 把 `pretty_dark = " Pretty Dark"` 加到 `extra/init.lua:16-20` 的 `styles` 表
2. 跑上面的生成命令
3. `extras/vim/colors/` 下会多出**一个** `tokyonight-pretty_dark.vim`（因为 `M.extras` 只注册了 vim 一个 exporter，所以每个 style 只生成这一份；kitty / ghostty 等要先在 `M.extras` 里注册对应 exporter 才谈得上，与 `cache.clear()` 无关）

### nvim 运行时缓存 vs extras 生成产物（别混淆）

两者完全无关，服务对象不同：

| 机制 | 路径 | 服务对象 | 改 lua 源码后的处理 |
|------|------|---------|-------------------|
| **nvim 运行时缓存** | `~/.cache/nvim/tokyonight-*.json` | Neovim 本身（加速启动） | `rm -rf ~/.cache/nvim/tokyonight*` |
| **extras 生成产物** | `extras/vim/colors/` 下的 `.vim` | 经典 Vim（非 nvim） | 重跑生成命令 |

- **缓存**：运行时加速用的 JSON 序列化，按 style 名作 key（见 `groups/init.lua:139`），靠 `inputs` 深比对自动失效（`groups/init.lua:149`），删了下次自动重建。三条路径要分清：① 主插件正常加载/换肤**不依赖**手动 `cache.clear()`，缓存靠上述 inputs 深比对自动失效；② `.lazy.lua` 的开发热重载（`BufWritePost`/`VeryLazy` → `M.reset()`）会显式调 `util.lua:164` 的 `cache.clear()` 强制清缓存；③ `cache.clear()` 内部的 `storm/day/night/moon` 列表与 extras 生成完全无关。故改色后想立即看到效果，改源码走开发热重载即可，无需手动清缓存
- **extras**：编译导出产物，因为经典 Vim 不能执行 lua，必须预先翻译成 `.vim` 的 `hi` 语句
