-- ================================
-- 基础编辑器选项
-- ================================

vim.g.mapleader = " "
vim.g.maplocalleader = "\\" -- 本地 leader（常用于 filetype/插件的局部映射）

local opt = vim.opt

-- 行号与当前行
opt.number = true -- 显示绝对行号
opt.relativenumber = true -- 显示相对行号（便于用 j/k 计数移动）
opt.cursorline = true -- 高亮当前行

-- 缩进与 Tab
opt.expandtab = true -- Tab 转为空格
opt.shiftwidth = 2 -- 自动缩进每级空格数（>>, <<, == 等）
opt.tabstop = 2 -- 一个 Tab 显示为多少空格宽度
opt.softtabstop = 2 -- 编辑时按 <Tab>/<BS> 视为多少空格
opt.autoindent = true -- 回车后复制上一行缩进（没有 indentexpr 时的基础兜底）
opt.smartindent = true -- C 风格 { 与 cinwords 的额外缩进；设了 indentexpr 的 filetype 会忽略它

-- 鼠标、确认、编码
opt.mouse = "a" -- 启用鼠标（普通/插入/可视等模式）
-- Shift+左键 扩展选区（需终端把 Shift+点击 发给 Neovim）。WezTerm 默认用 Shift 绕过鼠标上报，需改 bypass 修饰键
opt.mousemodel = "extend"
opt.confirm = true -- 未保存缓冲区退出/切换时弹出确认
opt.encoding = "utf-8" -- Neovim 内部使用的编码
opt.fileencoding = "utf-8" -- 写入文件时使用的编码

-- 搜索与补全
opt.ignorecase = true -- 搜索默认忽略大小写
opt.smartcase = true -- 搜索包含大写时自动区分大小写
opt.completeopt = "menu,menuone,noselect" -- 补全菜单行为（配合 nvim-cmp 等）

-- 外观
opt.termguicolors = true -- 启用 24-bit 真彩
-- 左侧栏完全交给 vv-statuscol 自绘（mark/sign/git/fold 都在 statuscolumn 内渲染）。
-- 原生 signcolumn 不走 %s，置 'yes' 只会白占 2 列；设 'no' 让插件按内容动态决定宽度
opt.signcolumn = "no"
opt.wrap = true -- 长行自动换行显示
opt.splitright = true -- 垂直分屏默认向右打开
opt.splitbelow = true -- 水平分屏默认向下打开
opt.scrolloff = 5 -- 光标距屏边 5 行
opt.list = true -- 显示不可见字符
opt.listchars = "tab:» ,nbsp:␣"

-- 光标形状与闪烁 (匹配终端呼吸效果)
opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175"

-- 撤销持久化（替代 swapfile 作为崩溃恢复手段）
opt.undofile = true -- 开启持久化撤销
opt.swapfile = false -- 禁用 swap，彻底消除多实例打开同一文件的警告
opt.autoread = true  -- 文件被外部修改时自动重载（多实例场景下保持内容最新）

-- 按键超时（ms）
opt.timeoutlen = 300

-- 文件保存策略
opt.backupcopy = "yes" -- 保存时原地覆写文件（保留 inode），避免 fd 失效导致日志器等进程丢数据

-- 禁用内置插件：netrw 由 vv-explorer 接管；必须在 plugin scripts source 之前设（即 init.lua 阶段）
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
