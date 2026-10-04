" 单文件 Vim 配置：复制到陌生机器的 ~/.vimrc 即可使用核心编辑功能，不依赖 Neovim
" 本机验收基线：Vim 9.2；最低版本未做整体验证，不保证旧版或精简构建完整可用
" 可视 sg / sw 使用 getregion(..., opts)，需 Vim 9.1.0142+，目前没有旧版回退；
" 内置终端需要 +terminal，持久撤销需要 +persistent_undo
"
" 可选依赖与降级：
"   rg：ff 在 findfunc / matchfuzzy 可用时使用文件列表 + 模糊补全，否则退回原生 :find；
"       sg / sw 未安装 rg 时使用默认 grepprg
"   git：状态栏分支查询依赖 git；查询失败时不显示分支
"   主题 / 图标 / 日志语法：借用本机 nvim vendor 数据，不运行 Lua；缺失时回退内置主题 / 文本图标 / 默认语法
"   smart-splits：可选 ~/.vim/mods/smart-splits.vim；缺失时使用原生 <C-w> 分栏操作
"   ts：tmux 内依赖 ~/.config/tmux/scripts/send-to-pane.sh 及 lib/nvim-detect.sh，缺失时提示错误；
"       不在 tmux 时改为复制路径；只复制 .vimrc 不会附带这些脚本
"   tt：tmux popup 依赖 ~/.config/tmux/scripts/popup-term.sh 及 cleanup-popup-sessions.sh；
"       入口脚本缺失、不在 tmux 或使用 GUI 时退回 Vim 内置 :terminal
"   剪贴板：本机读写依赖 Vim 的 +clipboard；OSC52 复制依赖终端 / tmux 支持，不提供远程读取
"            WSL 复制使用 win32yank.exe 或 clip.exe，详见剪贴板块
"
" 导航（按文件顺序，无易过期的行号）：
"   基础与编码 → 可选运行时 → 主题色 → 光标形状 → 基础按键与鼠标 → 撤销粒度 → 常用快捷键
"   → 基本显示 → 状态栏 → 缩进 → 文档注释 → 屏幕行导航与编辑 → 搜索跳转与高亮
"   → 文件查找 ff → 文本搜索 sg / sw → 缓冲区与最近文件 fb / fr → 剪贴板 → Yank 闪烁
"   → 光标位置恢复 → 提权保存 → 文件持久化与自动重读 → 保存前处理 → 窗口尺寸与文件类型
"   → 路径复制 fy → tmux 路径发送 ts → 终端切换 tt → 缓冲区关闭 bd / bD / bo → MiniExplorer
" 定位：搜索块标题或快捷键；在 Vim 中输入 /^" === 可逐个跳转一级块
"
" ================= 基础与编码 =================
" 禁用过时的 vi 兼容模式
set nocompatible
set lazyredraw  " 在执行宏或脚本时不重绘屏幕，提升速度

" 设置编码，防止乱码
set encoding=utf-8
scriptencoding utf-8
set fileencodings=utf-8,ucs-bom,gb18030,gbk,gb2312,cp936


" ================= 可选运行时（日志语法） =================
" vv-log-hl.nvim 的高亮逻辑在 Lua 里，只供 Neovim 使用；这里仅借用它的 ftdetect/ 与 syntax/（log 文件语法）
if isdirectory(expand('~/.config/nvim/vendors/vv-log-hl.nvim'))
  set runtimepath+=~/.config/nvim/vendors/vv-log-hl.nvim
endif


" ================= 主题色 =================
syntax on
set background=dark

" 真彩判断：终端声明支持 24-bit，或位于 tmux 内（tmux 的 terminal-features 默认 *:RGB）
let s:truecolor = has('gui_running') || (has('termguicolors')
  \ && ($COLORTERM =~# 'truecolor\|24bit'
  \   || $TERM =~# 'kitty\|wezterm\|ghostty\|direct'
  \   || $TMUX !=# ''))

if s:truecolor && !has('gui_running')
  " 旧版 Vim 不会为非 xterm 的 $TERM 填充真彩色转义码，缺失时手动补上
  if &t_8f ==# ''
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  endif
  " 启用真彩色支持（Kitty/WezTerm/Ghostty 必须开启这个才有漂亮颜色）
  set termguicolors
endif

" 主题负责具体颜色（包括导出的 SL* / MiniExplorerIcon*），这里只建立缺省语义链接
" default 不覆盖主题已定义的组；主题缺失或切换到其他配色时，仍能显示状态栏和文件树
" ColorScheme 后补回链接，避免 hi clear 留下未定义的 UI 组；不覆盖标准主题高亮
function! s:SetupUIHighlights() abort
  hi default link SLModeN Statement
  hi default link SLModeI String
  hi default link SLModeV PreProc
  hi default link SLModeR ErrorMsg
  hi default link SLModeC WarningMsg
  hi default link SLGit Directory
  hi default link SLFile StatusLine
  hi default link SLMod ErrorMsg
  hi default link SLFill StatusLine
  hi default link SLFt Type
  hi default link SLPos StatusLine

  hi default link MiniExplorerIconDefault Normal
  hi default link MiniExplorerIconBlue Directory
  hi default link MiniExplorerIconCyan Special
  hi default link MiniExplorerIconGreen String
  hi default link MiniExplorerIconYellow WarningMsg
  hi default link MiniExplorerIconOrange Number
  hi default link MiniExplorerIconRed ErrorMsg
  hi default link MiniExplorerIconPurple PreProc
  hi default link MiniExplorerIconMagenta PreProc
  hi default link MiniExplorerIconGrey Comment
  hi default link MiniExplorerIconGray Comment
  hi default link MiniExplorerIconWhite Normal
  hi default link MiniExplorerDir Directory
  hi default link MiniExplorerFile Normal
endfunction

augroup my_highlights
  autocmd!
  autocmd ColorScheme * call s:SetupUIHighlights()
augroup END

" 主题直接取 tokyonight.nvim 仓库导出的 Vim 配色：把 extras/vim 加入 runtimepath 后按名加载，
" 不依赖 ~/.vim/colors 下的软链接；非真彩终端或主题缺失时回退到内置 habamax
let s:theme_rtp = expand('~/.config/nvim/vendors/tokyonight.nvim/extras/vim')
let s:theme_ok = 0
if s:truecolor && isdirectory(s:theme_rtp . '/colors')
  execute 'set runtimepath+=' . fnameescape(s:theme_rtp)
  try
    colorscheme tokyonight-pretty_cat
    let s:theme_ok = 1
  catch
  endtry
endif
if !s:theme_ok
  silent! colorscheme habamax
endif
" colorscheme 不存在时不会触发 ColorScheme，这里兜底应用一次
if !exists('g:colors_name')
  call s:SetupUIHighlights()
endif
unlet s:theme_rtp s:theme_ok


" ================= 光标形状切换 =================
" 插入模式用竖线 (Beam)，普通模式用方块 (Block)
let &t_SI = "\e[5 q" " 竖线
let &t_EI = "\e[1 q" " 方块
let &t_SR = "\e[3 q" " 下划线 (替换模式)
" 启动时立即发送方块光标码——vim 不会因 "进入 Normal" 触发 t_EI
" 故光标会继承 SSH/终端的当前形状（通常是 beam）；t_ti 在接管终端时发送可修复这一问题
let &t_ti .= "\e[1 q"


" ================= 基础按键与鼠标 =================
" Leader / 模式切换
let mapleader = " "
let maplocalleader = "\\"

" 映射不支持行尾注释（注释会成为 rhs 的一部分），注释须单独成行
" 在插入模式下，jk 快速退出到 Normal 模式
inoremap jk <Esc>
" 按 Esc 键清除搜索高亮（<Cmd> 不切换模式，也不会因 Normal 下多余的 <Esc> 响铃）
nnoremap <silent> <Esc> <Cmd>nohlsearch<CR>

" 鼠标支持（仅 normal 和 visual 模式，允许点击定位和选中文本）
set mouse=nv
" 右键弹出菜单并把光标移到点击处（与 Neovim 默认一致）
set mousemodel=popup_setpos
" SGR 鼠标协议：tmux 下 Vim 只会自动选 xterm 协议，超过 223 列的点击会错位
if has('mouse_sgr')
  set ttymouse=sgr
endif

" 未保存缓冲区退出/切换时弹出确认
set confirm


" ================= 撤销粒度 =================
" 连续 Insert 默认只生成一个 undo block；与 Neovim 一致，在空格和标点后拆分
let s:undo_separator_codes = [32]

for s:range in [[33, 47], [58, 64], [91, 96], [123, 126]]
  call extend(s:undo_separator_codes, range(s:range[0], s:range[1]))
endfor

let s:undo_separators = [
  \ '，', '。', '！', '？', '；', '：', '、', '…', '—', '–', '·', '￥',
  \ '“', '”', '‘', '’', '「', '」', '『', '』',
  \ '（', '）', '【', '】', '〔', '〕', '［', '］', '｛', '｝', '〈', '〉', '《', '》',
  \ '＂', '＃', '＄', '％', '＆', '＇', '＊', '＋', '－', '．', '／',
  \ '＜', '＝', '＞', '＠', '＼', '＾', '＿', '｀', '｜', '～',
  \ ]

call extend(s:undo_separator_codes, map(s:undo_separators, 'char2nr(v:val)'))

for s:code in s:undo_separator_codes
  execute printf('inoremap <Char-%d> <Char-%d><C-g>u', s:code, s:code)
endfor

unlet s:code s:range s:undo_separator_codes s:undo_separators


" ================= 常用快捷键（VSCode 风格） =================
" 缩短等待时间，避免按 Esc 后产生 ~1s 延迟
set ttimeoutlen=20
" 映射序列（<Leader> 组合键等）的等待时间，与 Neovim 一致
set timeoutlen=300

" C-s 保存当前文件；C-A-s 保存所有
" 终端若吞掉 C-s（流控），在 shell 中执行 stty -ixon
nnoremap <silent> <C-s> <Cmd>w<CR>
inoremap <silent> <C-s> <Cmd>w<CR>
xnoremap <silent> <C-s> <Cmd>w<CR><Esc>
nnoremap <silent> <C-A-s> <Cmd>wa<CR>
inoremap <silent> <C-A-s> <Cmd>wa<CR>
xnoremap <silent> <C-A-s> <Cmd>wa<CR><Esc>

" Alt + Up/Down 上下移动当前行 / 选中行（首末行越界时静默，不报 E16）
nnoremap <silent> <A-Down> <Cmd>silent! move .+1<CR>==
nnoremap <silent> <A-Up> <Cmd>silent! move .-2<CR>==
xnoremap <silent> <A-Down> :<C-u>silent! '<,'>move '>+1<CR>gv=gv
xnoremap <silent> <A-Up> :<C-u>silent! '<,'>move '<-2<CR>gv=gv

" Normal / Visual 模式 Tab / Shift-Tab 缩进 / 反缩进，visual 保持选中
" 注意：normal 模式 <Tab> 与 <C-i> 共用同一键码，会覆盖跳转前进；已由 <A-Right> 承接
nnoremap <Tab> >>
nnoremap <S-Tab> <<
xnoremap <Tab> >gv
xnoremap <S-Tab> <gv

" Alt + Left/Right 光标跳转历史（类似 VSCode 导航前进/后退）
nnoremap <silent> <A-Left> <C-o>
nnoremap <silent> <A-Right> <C-i>

" Buffer 切换：补齐 Neovim 0.11+ 内置的 [b / ]b / [B / ]B（Vim 默认没有）
nnoremap <silent> [b <Cmd>bprevious<CR>
nnoremap <silent> ]b <Cmd>bnext<CR>
nnoremap <silent> [B <Cmd>bfirst<CR>
nnoremap <silent> ]B <Cmd>blast<CR>

" C-e / C-y 无计数时滚动 5 行，带计数时按计数滚动（与 Neovim 一致，仅 normal）
nnoremap <expr> <C-e> v:count ? '<C-e>' : '5<C-e>'
nnoremap <expr> <C-y> v:count ? '<C-y>' : '5<C-y>'

" 分屏：<Leader>- 水平、<Leader>| 垂直
nnoremap <silent> <Leader>- <C-w>s
nnoremap <silent> <Leader><Bar> <C-w>v

" 可选增强：Ctrl+Alt 分栏导航 / 缩放；模块缺失不影响单文件核心配置
if filereadable(expand('~/.vim/mods/smart-splits.vim'))
  source ~/.vim/mods/smart-splits.vim
endif


" ================= 基本显示设置 =================
set number          " 显示行号
set relativenumber  " 显示相对行号（光标行绝对，其余相对）
set cursorline      " 高亮当前行

set showcmd         " 显示部分命令
set wildmenu        " 命令补全菜单

set hidden          " 允许切换未保存的缓冲区
set list            " 可视化不可见字符（空格/Tab 诊断）
set listchars=tab:»\ ,nbsp:␣
set completeopt=menu,menuone,noselect " 补全菜单更现代

set scrolloff=5           " 光标距屏边 5 行
set wrap                  " 自动换行

" 自动检测文件类型并加载插件和缩进规则
filetype plugin indent on

" 自然的分屏方向
set splitbelow        " 水平拆分在下方打开
set splitright        " 垂直拆分在右方打开


" ================= 状态栏（模式 / 分支 / 编码 / 位置） =================
set laststatus=2  " 始终显示状态栏
set noshowmode    " 状态栏已显示模式，不再底部重复

let s:sl_mode_map = {
  \ 'n': 'NORMAL', 'no': 'N·OP',
  \ 'v': 'VISUAL', 'V': 'V·LINE', "\<C-v>": 'V·BLOCK',
  \ 's': 'SELECT', 'S': 'S·LINE', "\<C-s>": 'S·BLOCK',
  \ 'i': 'INSERT', 'ic': 'INSERT',
  \ 'R': 'REPLACE', 'Rv': 'V·REPL',
  \ 'c': 'COMMAND', 't': 'TERM',
  \ }

" 模式 → 高亮组后缀（SLModeN/I/V/R/C 由主题定义，缺失时使用 SetupUIHighlights 的语义链接）
function! s:SLModeGroup(mode) abort
  if a:mode =~# '^[vVsS]' || a:mode ==# "\<C-v>" || a:mode ==# "\<C-s>"
    return 'V'
  elseif a:mode =~# '^R'
    return 'R'
  elseif a:mode =~# '^[it]'
    return 'I'
  elseif a:mode ==# 'c'
    return 'C'
  endif
  return 'N'
endfunction

" 'statusline' 以 %! 求值：g:statusline_winid 指向正在绘制的窗口，非当前窗口只用中性色（StatusLineNC）
function! s:StatusLine() abort
  if g:statusline_winid != win_getid()
    return ' %f %m%r%= %l:%c %p%% '
  endif

  let l:mode = mode()
  return '%#SLMode' . s:SLModeGroup(l:mode) . '# ' . get(s:sl_mode_map, l:mode, l:mode) . ' '
    \ . '%#SLGit# %{get(b:, "sl_git", "")}'
    \ . '%#SLFile#%f '
    \ . '%#SLMod#%m%r'
    \ . '%#SLFill#%='
    \ . '%#SLFt# %{&filetype} '
    \ . '%#SLFill# %{&fileencoding !=# "" ? &fileencoding : &encoding} '
    \ . '%#SLPos# %l:%c %p%% '
endfunction

" git 分支缓存在 buffer 变量里，仅在切换 buffer / 写入 / 焦点回来时刷新，避免每次重绘都调 shell
" 以文件所在目录为准（而不是 cwd），无名 buffer 回退到 cwd；特殊 buffer 不显示
function! s:SLUpdateGit() abort
  if &buftype !=# ''
    return
  endif

  let l:dir = expand('%') ==# '' ? getcwd() : expand('%:p:h')
  if !isdirectory(l:dir)
    let b:sl_git = ''
    return
  endif

  let l:out = systemlist('git -C ' . shellescape(l:dir) . ' rev-parse --abbrev-ref HEAD 2>/dev/null')
  let b:sl_git = (!v:shell_error && len(l:out) && l:out[0] !=# '') ? l:out[0] . '  ' : ''
endfunction

augroup SLGit
  autocmd!
  autocmd BufEnter,BufWritePost,FocusGained * call s:SLUpdateGit()
augroup END

let &statusline = '%!' . expand('<SID>') . 'StatusLine()'


" ================= 缩进与 Tab 设置 =================
set tabstop=2       " Tab 显示为 2 空格宽
set shiftwidth=2    " 缩进宽度为 2 空格
set softtabstop=2   " 编辑时 <Tab>/<BS> 视为 2 空格
set expandtab       " Tab 键插入空格而非 Tab 字符
set autoindent      " 新行复制当前行缩进
set smartindent     " 智能缩进（适用于 C-like 代码）
set backspace=indent,eol,start  " 允许退格删除

" 关闭在插入模式下按回车自动延续注释符号
" 已注释：开启以支持 /** */ 文档注释 * 续写
" augroup my_no_comment_continuation
"   autocmd!
"   autocmd FileType * setlocal formatoptions-=r formatoptions-=o
" augroup END


" ================= 文档注释智能编辑 =================
" 1. /** 自动闭合：输入 /* 后再按 * → /**  */，光标留在中间
" 2. Enter 展开：/** | */ 内按回车 → 三行展开，光标停在 * 行
" 3. * 续写由 formatoptions r/o 处理
" 映射用 <expr> 直接返回按键：不经 feedkeys 补键，快速输入、宏与 . 重复时按键顺序不会错乱

" 返回光标前后的文本 [before, after]
function! s:SplitAtCursor() abort
  let l:line = getline('.')
  let l:col = col('.') - 1
  return [strpart(l:line, 0, l:col), strpart(l:line, l:col)]
endfunction

function! s:DocCommentStar() abort
  let [l:before, l:after] = s:SplitAtCursor()
  if l:before =~# '/\*$' && l:after !~# '^\s*\*/'
    " 补出 "*  */" 后左移 3 格停在两空格中间；<C-g>U 让左移不拆分 undo / . 重复
    return "*  */\<C-g>U\<Left>\<C-g>U\<Left>\<C-g>U\<Left>"
  endif
  " 本映射覆盖了全局 * 的 undo 拆分映射，这里补回
  return "*\<C-g>u"
endfunction

function! s:DocCommentEnter() abort
  " 补全菜单可见时 Enter 只确认补全
  if pumvisible()
    return "\<C-y>"
  endif

  let [l:before, l:after] = s:SplitAtCursor()
  if l:before =~# '/\*\*\s*$' && l:after =~# '^\s*\*/'
    " 多行改写需要修改 buffer，<expr> 求值期间不允许，交给 <Cmd> 在映射返回后执行
    return "\<Cmd>call " . expand('<SID>') . "DocCommentExpand()\<CR>"
  endif
  return "\<CR>"
endfunction

function! s:DocCommentExpand() abort
  let [l:before, l:after] = s:SplitAtCursor()
  let l:indent = matchstr(getline('.'), '^\s*')
  let l:row = line('.')
  call setline(l:row, substitute(l:before, '\s\+$', '', ''))
  call append(l:row, [l:indent . ' * ', l:indent . ' ' . substitute(l:after, '^\s\+', '', '')])
  call cursor(l:row + 1, len(l:indent) + 4)
endfunction

augroup my_doc_comment
  autocmd!
  autocmd FileType javascript,typescript,typescriptreact,javascriptreact,vue,java,c,cpp,css,scss,less,rust,go,php
    \ inoremap <buffer> <expr> * <SID>DocCommentStar()
  autocmd FileType javascript,typescript,typescriptreact,javascriptreact,vue,java,c,cpp,css,scss,less,rust,go,php
    \ inoremap <buffer> <expr> <CR> <SID>DocCommentEnter()
augroup END


" ================= 屏幕行导航与编辑（j / k / $ / A / I / Y） =================
" j/k 按屏幕行移动（长行 wrap 时体验与 VSCode 一致），带数字前缀时按实际行跳
nnoremap <expr> j v:count == 0 ? 'gj' : 'j'
nnoremap <expr> k v:count == 0 ? 'gk' : 'k'
xnoremap <expr> j v:count == 0 ? 'gj' : 'j'
xnoremap <expr> k v:count == 0 ? 'gk' : 'k'

" $ / A / I 同样按屏幕行（行尾 / 行首非空白），带数字前缀时保持原生行为
" 当前行没有折行时屏幕行就是整行，直接用原生键：保留 A 的 . 重复语义、$ 的列粘滞与块选区 $ 行为
function! s:LineWraps() abort
  if !&wrap
    return 0
  endif
  let l:width = winwidth(0) - getwininfo(win_getid())[0].textoff
  return virtcol('$') - 1 > l:width
endfunction

nnoremap <expr> $ v:count == 0 && <SID>LineWraps() ? 'g$' : '$'
xnoremap <expr> $ v:count == 0 && <SID>LineWraps() ? 'g$' : '$'
nnoremap <expr> A v:count == 0 && <SID>LineWraps() ? 'g$a' : 'A'

" 屏幕行版 I：跳到当前屏幕行起点后的第一个非空白字符再进入插入
function! s:DisplayLineInsert() abort
  normal! g0
  let l:idx = match(getline('.'), '\S', col('.') - 1)
  if l:idx >= 0
    call cursor(line('.'), l:idx + 1)
  endif
  startinsert
endfunction
nnoremap <expr> I v:count == 0 && <SID>LineWraps() ? '<Cmd>call <SID>DisplayLineInsert()<CR>' : 'I'

" Y：与 D/C 对齐，复制光标到行尾（修正 Vim 历史遗留的 Y=yy 行为）
nnoremap Y y$


" ================= 搜索跳转与高亮 =================
set ignorecase      " 搜索忽略大小写
set incsearch       " 增量搜索（边输入边匹配）
set hlsearch        " 高亮搜索结果
set smartcase       " 智能大小写（输入大写时才区分大小写）

" 搜索结果居中：按 n 或 N 跳转时，始终让匹配行处于屏幕中间，视线不乱跳
nnoremap n nzz
nnoremap N Nzz
nnoremap * *zz
nnoremap # #zz

" 进入插入模式时清除搜索高亮；autocmd 内直接 :nohlsearch 会在返回时被恢复（timer 回调同样无效），故塞回输入队列
" 必须用 'i' 插到队首：追加到队尾（'n'）在录制宏时会截断 q 寄存器（实测 qqAm<Esc>q 只录下 A）
augroup my_clear_search
  autocmd!
  autocmd InsertEnter * if v:hlsearch | call feedkeys("\<Cmd>nohlsearch\<CR>", 'ni') | endif
augroup END


" ================= 文件查找（<Leader>ff，原生 :find） =================
" <Leader>ff：:find 文件；有 'findfunc'（Vim 9.1.0831+）时用 rg 列文件 + matchfuzzy 模糊匹配，否则回退 path+=**
if exists('+findfunc') && executable('rg') && exists('*matchfuzzy')
  let s:find_cache = []

  function! s:FindFiles(arg, cmdcomplete) abort
    " 每次进入命令行只跑一次 rg，补全时逐键复用
    if empty(s:find_cache)
      let s:find_cache = systemlist('rg --files --hidden --glob "!.git"')
    endif
    return a:arg ==# '' ? copy(s:find_cache) : matchfuzzy(s:find_cache, a:arg)
  endfunction

  let &findfunc = expand('<SID>') . 'FindFiles'

  augroup my_find_cache
    autocmd!
    autocmd CmdlineEnter : let s:find_cache = []
  augroup END
else
  set path+=**
endif
nnoremap <Leader>ff :find<Space>


" ================= 文本搜索（<Leader>sg / sw，quickfix） =================
" <Leader>sg / <Leader>sw：安装 rg 时 :grep 走 ripgrep，否则保留 Vim 默认 grepprg
if executable('rg')
  set grepprg=rg\ --vimgrep\ --smart-case grepformat=%f:%l:%c:%m
endif

" 固定字符串搜索：shellescape 第二参数转义 % # ! 等 cmdline 特殊字符
function! s:GrepText(text, word) abort
  if a:text ==# ''
    return
  endif
  execute 'silent grep! ' . (a:word ? '-w ' : '') . '-F -- ' . shellescape(a:text, 1)
endfunction

augroup my_grep_qf
  autocmd!
  autocmd QuickFixCmdPost grep,grepadd,vimgrep,vimgrepadd cwindow | redraw!
augroup END

nnoremap <Leader>sg :silent grep!<Space>
nnoremap <silent> <Leader>sw <Cmd>call <SID>GrepText(expand('<cword>'), 1)<CR>
xnoremap <silent> <Leader>sg <Cmd>call <SID>GrepText(getregion(getpos('v'), getpos('.'), {'type': mode()})[0], 0)<CR><Esc>
xnoremap <silent> <Leader>sw <Cmd>call <SID>GrepText(getregion(getpos('v'), getpos('.'), {'type': mode()})[0], 0)<CR><Esc>


" ================= 缓冲区与最近文件（<Leader>fb / fr） =================
" <Leader>fb：列出 buffer 后输入编号/名称切换；<Leader>fr：最近文件
nnoremap <Leader>fb :ls<CR>:buffer<Space>
nnoremap <silent> <Leader>fr <Cmd>browse oldfiles<CR>


" ================= 剪贴板与寄存器（WSL / SSH / Mac / Linux） =================
" 1. 黑洞寄存器映射 (解决 x/d/c 等污染问题)
"    只在未显式指定寄存器时走黑洞："ad / "ax 等仍写入指定寄存器
"    clipboard=unnamed / unnamedplus 时，不带前缀的 v:register 分别是 * / +
function! s:DefaultRegister() abort
  return &clipboard =~# 'unnamedplus' ? '+' : &clipboard =~# 'unnamed' ? '*' : '"'
endfunction

function! s:BlackHole(key) abort
  return (v:register ==# s:DefaultRegister() ? '"_' : '') . a:key
endfunction

" 可视模式 x 剪切到系统剪贴板（与 Neovim 一致）
function! s:VisualCut() abort
  if v:register !=# s:DefaultRegister()
    return 'x'
  endif
  return has('clipboard') ? '"+x' : 'x'
endfunction

for s:key in ['d', 'D', 'c', 'C', 'x', 'X']
  execute printf('nnoremap <expr> %s <SID>BlackHole(%s)', s:key, string(s:key))
endfor
for s:key in ['d', 'D', 'c', 'C', 'X']
  execute printf('xnoremap <expr> %s <SID>BlackHole(%s)', s:key, string(s:key))
endfor
unlet s:key
xnoremap <expr> x <SID>VisualCut()

" 粘贴时按当前行调整缩进（与 Neovim 一致）
nnoremap p ]p
nnoremap P [p

" 2. 跨平台剪贴板整合
"    只同步 yank 到无名 / 系统寄存器的内容；"ay 等写命名寄存器不外发
function! s:IsClipboardYank() abort
  return index(['', '+', '*'], v:event.regname) >= 0
endfunction

if has('wsl') || $WSL_DISTRO_NAME !=# ''
  " WSL 环境：使用 win32yank 或 clip.exe 同步到 Windows
  let g:clipboard_cmd = 'win32yank.exe'
  if executable(g:clipboard_cmd)
    " 如果安装了 win32yank.exe (Neovim默认推荐方案)
    function! s:CopyToSystem(lines) abort
      call system('win32yank.exe -i --crlf', join(a:lines, "\n"))
    endfunction
    " 因为纯 Vim 在 WSL 中很难真正支持 clipboard=unnamedplus
    " 所以这里覆盖 p 键，让 p 强制从 Windows 剪贴板读取粘贴
    nnoremap <silent> p :let @"=system('win32yank.exe -o --lf')<CR>]p
    nnoremap <silent> P :let @"=system('win32yank.exe -o --lf')<CR>[p
  else
    " 降级：仅用 clip.exe 复制到 Windows，粘贴请在终端使用 Ctrl+Shift+V
    function! s:CopyToSystem(lines) abort
      call system('clip.exe', join(a:lines, "\n"))
    endfunction
  endif

  augroup WSLYank
    autocmd!
    autocmd TextYankPost * if s:IsClipboardYank() | call s:CopyToSystem(v:event.regcontents) | endif
  augroup END

elseif has('mac') || has('unix')
  " paste 方向：Vim 带 +clipboard 时直接读写本机系统剪贴板（macOS 只有 unnamed）
  if has('unnamedplus')
    set clipboard=unnamedplus
  else
    set clipboard=unnamed
  endif

  " copy 方向：额外发 OSC52（对齐 nvim clipboard.lua 的写方向策略）
  "   - 本地：系统剪贴板已由 'clipboard' 写入，OSC52 冗余无害
  "   - SSH / tmux attach：OSC52 到达当前所在终端（不论 Vim 是否带 +clipboard）
  "   不在启动时判断 $SSH_TTY，避免持久化 tmux 里被冻结；GUI 没有终端通道，不发
  function! s:CopyToSystem(lines) abort
    if has('gui_running')
      return
    endif

    if exists('*base64_encode') && exists('*str2blob') && exists('*echoraw')
      call echoraw("\e]52;c;" . base64_encode(str2blob(a:lines)) . "\x07")
      return
    endif

    " 旧版 Vim：交给 shell 编码，去掉 base64 输出中的换行（GNU base64 每 76 列折行）
    let l:b64 = substitute(system('base64', join(a:lines, "\n")), '\n', '', 'g')
    silent! call system('printf %s ' . shellescape("\e]52;c;" . l:b64 . "\x07") . ' > /dev/tty')
  endfunction

  augroup UnixYank
    autocmd!
    autocmd TextYankPost * if s:IsClipboardYank() | call s:CopyToSystem(v:event.regcontents) | endif
  augroup END
endif

" 把文本放进系统剪贴板（供 CopyPathLine 等命令使用；setreg 不触发 TextYankPost，需手动外发）
function! s:CopyText(text) abort
  call setreg(has('clipboard') ? '+' : '"', a:text)
  if exists('*s:CopyToSystem')
    call s:CopyToSystem(split(a:text, "\n", 1))
  endif
endfunction

" ================= 可视模式复制与 Yank 闪烁 =================
" 1. 选中模式下按 Ctrl-C 复制到系统剪贴板 (类似 Neovim)
if has('clipboard')
  xnoremap <silent> <C-c> "+y
else
  xnoremap <silent> <C-c> y
endif

" 2. 复制时闪烁视觉反馈：Vim 9.1+ 自带 hlyank 包（与 Neovim 的 on_yank 相同，用 IncSearch 组）
let g:hlyank_hlgroup = 'IncSearch'
let g:hlyank_duration = 200
if !empty(globpath(&packpath, 'pack/*/opt/hlyank', 0, 1))
  packadd! hlyank
elseif exists('*matchaddpos') && exists('*timer_start')
  " 旧版回退：纯 Vimscript 实现
  function! s:ClearYankHighlight(match_id, win_id, timer_id) abort
    " 指定窗口删除，yank 后 200ms 内切走窗口也不会残留
    silent! call matchdelete(a:match_id, a:win_id)
  endfunction

  function! s:FlashYank() abort
    if v:event.operator !=# 'y' | return | endif
    let l:sl = line("'[")
    let l:el = line("']")
    let l:positions = []
    if l:sl == l:el
      " 单行：用列范围精确高亮，避免前导空格也被覆盖
      let l:sc = col("'[")
      let l:ec = col("']")
      call add(l:positions, [l:sl, l:sc, l:ec - l:sc + 1])
    else
      " 多行：整行高亮（含缩进），限制行数防止卡顿
      let l:positions = range(l:sl, min([l:el, l:sl + 100]))
    endif
    let l:match_id = matchaddpos(g:hlyank_hlgroup, l:positions)
    call timer_start(g:hlyank_duration, function('s:ClearYankHighlight', [l:match_id, win_getid()]))
  endfunction

  augroup YankHighlight
    autocmd!
    " 所有的 yank 操作都会触发此闪烁
    autocmd TextYankPost * call s:FlashYank()
  augroup END
endif


" ================= 光标位置恢复 =================
" 自动恢复光标位置：重新打开文件时，回到上次关闭时的位置（提交信息除外）
augroup my_last_loc
  autocmd!
  autocmd BufReadPost * if &filetype !=# 'gitcommit' && line("'\"") >= 1 && line("'\"") <= line('$')
    \ | execute 'normal! g`"'
    \ | endif
augroup END


" ================= 提权保存（:W / <Leader>W） =================
" sudo 补刀：:W 或 <Leader>W 提权写入
" 原理：
"   1. :w !cmd 走 PTY，sudo 密码提示正常出现
"   2. :w !cmd 中 | 被当作 shell pipe，所以 | setlocal 无法可靠运行
"   3. 用 shell && touch marker 检测是否真正写入成功，再决定是否清 modified 标志
"   4. setlocal nomodified 比 edit! 好：不丢 undo 历史，不重载文件
"   5. shellescape 第二参数转义 % # ! 等，防止文件名被 :w !cmd 二次展开
function! s:SudoWrite() abort
  let l:marker = tempname()
  execute 'write !sudo tee ' . shellescape(expand('%:p'), 1) . ' >/dev/null && touch ' . shellescape(l:marker, 1)
  if filereadable(l:marker)
    call delete(l:marker)
    setlocal nomodified
  else
    echohl ErrorMsg | echom 'SudoWrite: 写入失败或密码错误' | echohl NONE
  endif
endfunction
command! W call s:SudoWrite()
nnoremap <silent> <Leader>W <Cmd>W<CR>


" ================= 文件持久化与自动重读 =================
" 持久化 undo 历史：集中放在 ~/.vim/undo，避免在项目目录旁生成 .xxx.un~
let s:undo_dir = expand('~/.vim/undo')
if !isdirectory(s:undo_dir)
  call mkdir(s:undo_dir, 'p', 0700)
endif
let &undodir = s:undo_dir . '//'
set undofile
unlet s:undo_dir

" 多实例编辑同一文件：禁用 swap 消除警告，autoread 保持内容最新
set noswapfile
set autoread
" 保存时原地覆写文件（保留 inode），避免 fd 失效导致日志器等进程丢数据
set backupcopy=yes
" 启用终端焦点事件上报（让 FocusGained 在终端 vim 中实际触发）
" Vim 不会为 tmux-256color 等 $TERM 自动填充，实测为空，不能省略
if &t_fe ==# ''
  let &t_fe = "\e[?1004h"
  let &t_fd = "\e[?1004l"
endif
" 命令行窗口（q:）内 :checktime 会报 E11；特殊 buffer 也无需检查
augroup my_checktime
  autocmd!
  autocmd FocusGained,BufEnter * if getcmdwintype() ==# '' && &buftype ==# '' | checktime | endif
augroup END


" ================= 保存前处理（目录 / 行尾空白） =================
" 保存前自动创建缺失目录（跳过 scp:// 等 URL）
function! s:AutoCreateDir(file) abort
  if a:file =~# '^\w\w\+:[\/][\/]'
    return
  endif
  let l:dir = fnamemodify(resolve(a:file), ':p:h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
endfunction

" 保存前删除行尾空白：无 filetype、markdown（行尾两空格是换行语法）与特殊 buffer 跳过
function! s:TrimTrailing() abort
  if &filetype ==# '' || &filetype ==# 'markdown' || &buftype !=# ''
    return
  endif
  let l:view = winsaveview()
  keeppatterns %s/\s\+$//e
  call winrestview(l:view)
endfunction

augroup my_save
  autocmd!
  autocmd BufWritePre * call s:AutoCreateDir(expand('<afile>'))
  autocmd BufWritePre * call s:TrimTrailing()
augroup END


" ================= 窗口尺寸与文件类型 =================
" 终端尺寸变化时，所有 tab 的分屏重新等分
function! s:EqualizeAllTabs() abort
  for l:tab in range(1, tabpagenr('$'))
    call win_execute(win_getid(1, l:tab), 'wincmd =')
  endfor
endfunction

" 帮助 / quickfix / man 页按 q 或 Esc 直接关闭（映射里的 | 会结束 rhs，故不在 autocmd 行内串接）
function! s:SetupCloseWithQ() abort
  setlocal nobuflisted
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> <Esc> <Cmd>close<CR>
endfunction

augroup my_filetype
  autocmd!
  autocmd VimResized * call s:EqualizeAllTabs()
  autocmd FileType help,qf,man call s:SetupCloseWithQ()
  " 文本 / 提交信息启用自动换行与拼写检查
  autocmd FileType text,plaintex,typst,gitcommit setlocal wrap spell
  " JSON Lines 按 JSON 高亮（Vim 默认识别为 jsonl）
  autocmd BufNewFile,BufRead *.jsonl,*.ndjson setlocal filetype=json
augroup END


" ================= 路径复制（<Leader>fy） =================
" 当前文件路径 + 行号：单行 path:42，多行 path:42-51；无文件名返回空串
function! s:PathLine(line1, line2) abort
  let l:path = expand('%:p')
  if l:path ==# ''
    return ''
  endif
  let [l:l1, l:l2] = a:line1 <= a:line2 ? [a:line1, a:line2] : [a:line2, a:line1]
  return l:l1 == l:l2 ? printf('%s:%d', l:path, l:l1) : printf('%s:%d-%d', l:path, l:l1, l:l2)
endfunction

function! s:Warn(msg) abort
  echohl WarningMsg | echomsg a:msg | echohl None
endfunction

" CopyPathLine：复制当前文件绝对路径 + 行号（成功静默，仅错误提示）
function! s:CopyPathLine(line1, line2) abort
  let l:text = s:PathLine(a:line1, a:line2)
  if l:text ==# ''
    call s:Warn('CopyPathLine: current buffer has no file path')
    return
  endif
  call s:CopyText(l:text)
endfunction
command! -range CopyPathLine call s:CopyPathLine(<line1>, <line2>)
nnoremap <silent> <Leader>fy <Cmd>CopyPathLine<CR>
xnoremap <silent> <Leader>fy :CopyPathLine<CR>


" ================= tmux 路径发送（<Leader>ts） =================
" 复用路径复制块的 PathLine / Warn；tmux 识别与投递由外部脚本负责，脚本缺失时不自动复制
" 发送路径到同 window 中第一个非 vim/nvim 的 tmux pane；不在 tmux 时退化为复制
function! s:SendPathToPane(line1, line2) abort
  let l:text = s:PathLine(a:line1, a:line2)
  if l:text ==# ''
    call s:Warn('Send path: current buffer has no file path')
    return
  endif

  if $TMUX ==# ''
    call s:CopyText(l:text)
    return
  endif

  let l:script = expand('~/.config/tmux/scripts/send-to-pane.sh')
  if !filereadable(l:script)
    echohl ErrorMsg | echomsg 'Script not found: ' . l:script | echohl None
    return
  endif

  call system(shellescape(l:script), ' ' . l:text . ' ')
  if v:shell_error
    call s:Warn('No target tmux pane found')
  endif
endfunction

nnoremap <silent> <Leader>ts <Cmd>call <SID>SendPathToPane(line('.'), line('.'))<CR>
xnoremap <silent> <Leader>ts <Cmd>call <SID>SendPathToPane(line('v'), line('.'))<CR><Esc>


" ================= 终端切换（<Leader>tt） =================
" 终端：tmux 下弹 tmux popup（常驻 scratch session，收起用 tmux 层的 C-`），否则切换底部 :terminal
let s:term_buf = -1
let s:popup_id = ''

function! s:ToggleTerm() abort
  let l:script = expand('~/.config/tmux/scripts/popup-term.sh')
  if $TMUX !=# '' && !has('gui_running') && exists('*job_start') && filereadable(l:script)
    " 实例级 id + 本进程 PID：popup-term.sh 的 cleanup 在 Vim 退出后回收 session
    if s:popup_id ==# ''
      let s:popup_id = printf('vim-%s-%d', substitute($TMUX_PANE, '[^A-Za-z0-9_-]', '', 'g'), getpid())
    endif
    " 可选参数缺省传 -（脚本约定，不能传空串）
    call job_start([l:script, getcwd(), s:popup_id, $TMUX_PANE !=# '' ? $TMUX_PANE : '-', string(getpid())])
    return
  endif

  let l:wins = s:term_buf > 0 ? win_findbuf(s:term_buf) : []
  call filter(l:wins, 'win_id2tabwin(v:val)[0] == tabpagenr()')
  if !empty(l:wins)
    call win_execute(l:wins[0], 'hide')
  elseif s:term_buf > 0 && bufexists(s:term_buf) && term_getstatus(s:term_buf) =~# 'running'
    execute 'botright sbuffer ' . s:term_buf
  else
    botright terminal
    let s:term_buf = bufnr('%')
  endif
endfunction

augroup my_popup_term
  autocmd!
  autocmd VimLeavePre * if s:popup_id !=# '' | call system('tmux kill-session -t ' . shellescape('=popup-' . s:popup_id)) | endif
augroup END

nnoremap <silent> <Leader>tt <Cmd>call <SID>ToggleTerm()<CR>
tnoremap <silent> <Leader>tt <Cmd>call <SID>ToggleTerm()<CR>


" ================= 缓冲区关闭（<Leader>bd / bD / bo） =================
" 警告提示复用路径复制块的 Warn
" 关闭缓冲区但保留窗口布局：显示它的窗口先切到其他 listed buffer（没有则新建空 buffer）
function! s:BufDelete(force) abort
  let l:buf = bufnr('%')

  if !a:force && getbufvar(l:buf, '&modified')
    let l:choice = confirm(printf('Save changes to "%s"?', bufname(l:buf) ==# '' ? '[No Name]' : bufname(l:buf)), "&Yes\n&No\n&Cancel", 3)
    if l:choice == 1
      write
    elseif l:choice != 2
      return
    endif
  endif

  let l:others = filter(range(1, bufnr('$')), 'buflisted(v:val) && v:val != l:buf')
  if empty(l:others)
    enew
    let l:target = bufnr('%')
  else
    let l:alt = bufnr('#')
    let l:target = index(l:others, l:alt) >= 0 ? l:alt : l:others[-1]
  endif

  for l:win in win_findbuf(l:buf)
    call win_execute(l:win, 'buffer ' . l:target)
  endfor
  if bufexists(l:buf)
    execute 'bdelete! ' . l:buf
  endif
endfunction

" 关闭其他 listed buffer；有未保存修改的跳过并提示
function! s:BufDeleteOthers() abort
  let l:skipped = 0
  for l:buf in filter(range(1, bufnr('$')), 'buflisted(v:val) && v:val != bufnr("%")')
    if getbufvar(l:buf, '&modified')
      let l:skipped += 1
    else
      execute 'bdelete ' . l:buf
    endif
  endfor
  if l:skipped
    call s:Warn(printf('Skipped %d modified buffer(s)', l:skipped))
  endif
endfunction

nnoremap <silent> <Leader>bd <Cmd>call <SID>BufDelete(0)<CR>
nnoremap <silent> <Leader>bD <Cmd>call <SID>BufDelete(1)<CR>
nnoremap <silent> <Leader>bo <Cmd>call <SID>BufDeleteOthers()<CR>


" ================= MiniExplorer（<Leader>e，纯 Vimscript 文件树） =================
" 目标：
"   1. 单文件 .vimrc 可分发，服务器上无需安装 nvim / 插件
"   2. 只做文件树概念：显示、展开、折叠、打开文件、定位当前文件
"   3. 若检测到 vv-icons.nvim 的 JSON 数据，则复用目录 / 文件图标；否则降级为纯文本符号

let s:me_buf = -1
let s:me_win = -1
let s:me_last_win = -1
let s:me_root = ''
let s:me_nodes = []
let s:me_expanded = {}

let s:me_icons = {
  \ 'arrow_closed': '',
  \ 'arrow_open': '',
  \ 'folder': {'glyph': '[D]', 'color': ''},
  \ 'folder_open': {'glyph': '[D]', 'color': ''},
  \ 'folder_empty': {'glyph': '[D]', 'color': ''},
  \ 'file': {'glyph': '[F]', 'color': ''},
  \ }

let s:me_file_icons = {}
let s:me_dir_icons = {}
let s:me_ext_icons = {}
let s:me_icon_matches = []

" ---------- 路径处理 ----------
function! s:MEPathNorm(path) abort
  let l:path = fnamemodify(a:path, ':p')
  let l:path = substitute(l:path, '[\/]\+$', '', '')
  return l:path ==# '' ? '/' : l:path
endfunction

function! s:MEPathJoin(dir, name) abort
  return a:dir =~# '[\/]$' ? a:dir . a:name : a:dir . '/' . a:name
endfunction

" path 是否位于 root 之下（两者均为 s:MEPathNorm 规范化后的绝对路径）
function! s:MEIsUnder(path, root) abort
  return a:root ==# '/' ? a:path =~# '^/' : stridx(a:path, a:root . '/') == 0
endfunction

function! s:MEResolveRoot(path) abort
  let l:raw = a:path ==# '' ? getcwd() : expand(a:path)

  if filereadable(l:raw)
    let l:raw = fnamemodify(l:raw, ':h')
  endif

  let l:root = s:MEPathNorm(l:raw)
  return isdirectory(l:root) ? l:root : s:MEPathNorm(getcwd())
endfunction

" ---------- 可选图标数据加载（vv-icons） ----------
function! s:MEReadJson(path, fallback) abort
  if !exists('*json_decode') || !filereadable(a:path)
    return a:fallback
  endif

  try
    return json_decode(join(readfile(a:path), "\n"))
  catch
    return a:fallback
  endtry
endfunction

function! s:MEFindIconDataDir() abort
  let l:candidates = [
    \ expand('~/.config/nvim/vendors/vv-icons.nvim/lua/vv-icons/data'),
    \ ]

  call extend(
    \ l:candidates,
    \ glob(expand('~/.local/share/nvim/site/pack/*/start/vv-icons.nvim/lua/vv-icons/data'), 0, 1),
    \ )

  call extend(
    \ l:candidates,
    \ glob(expand('~/.local/share/nvim/site/pack/*/opt/vv-icons.nvim/lua/vv-icons/data'), 0, 1),
    \ )

  for l:dir in l:candidates
    if isdirectory(l:dir)
      return l:dir
    endif
  endfor

  return ''
endfunction

function! s:MEIconEntry(entry, fallback) abort
  if type(a:entry) == type({}) && has_key(a:entry, 'glyph')
    return {
      \ 'glyph': a:entry.glyph,
      \ 'color': get(a:entry, 'color', get(a:fallback, 'color', '')),
      \ }
  endif

  return copy(a:fallback)
endfunction

function! s:MEIsExactIconMatch(match) abort
  return a:match !~# '[{}*?,]'
endfunction

function! s:MELoadIconList(entries) abort
  let l:icons = {}

  if type(a:entries) != type([])
    return l:icons
  endif

  for l:entry in a:entries
    if type(l:entry) != type({})
      continue
    endif

    if !has_key(l:entry, 'match') || !has_key(l:entry, 'glyph')
      continue
    endif

    if s:MEIsExactIconMatch(l:entry.match)
      let l:icons[l:entry.match] = s:MEIconEntry(l:entry, s:me_icons.file)
    endif
  endfor

  return l:icons
endfunction

function! s:MELoadIcons() abort
  let l:data_dir = s:MEFindIconDataDir()
  if l:data_dir ==# ''
    return
  endif

  let l:ui = s:MEReadJson(l:data_dir . '/ui.json', {})
  if type(l:ui) == type({})
    let s:me_icons.folder = s:MEIconEntry(get(l:ui, 'folder', {}), s:me_icons.folder)
    let s:me_icons.folder_open = s:MEIconEntry(get(l:ui, 'folder_open', {}), s:me_icons.folder_open)
    let s:me_icons.folder_empty = s:MEIconEntry(get(l:ui, 'folder_empty', {}), s:me_icons.folder_empty)
  endif

  let s:me_file_icons = s:MELoadIconList(s:MEReadJson(l:data_dir . '/files.json', []))
  let s:me_dir_icons = s:MELoadIconList(s:MEReadJson(l:data_dir . '/directories.json', []))

  let l:ext = s:MEReadJson(l:data_dir . '/extensions.json', {})
  if type(l:ext) == type({})
    let s:me_ext_icons = l:ext
  endif
endfunction

function! s:MEFileIcon(name) abort
  if has_key(s:me_file_icons, a:name)
    return s:me_file_icons[a:name]
  endif

  let l:ext = tolower(fnamemodify(a:name, ':e'))
  if l:ext !=# '' && has_key(s:me_ext_icons, l:ext)
    return s:MEIconEntry(s:me_ext_icons[l:ext], s:me_icons.file)
  endif

  return copy(s:me_icons.file)
endfunction

function! s:MEDirIcon(name, open, empty) abort
  if a:empty
    return copy(s:me_icons.folder_empty)
  endif

  if has_key(s:me_dir_icons, a:name)
    return s:me_dir_icons[a:name]
  endif

  return copy(a:open ? s:me_icons.folder_open : s:me_icons.folder)
endfunction

call s:MELoadIcons()

" ---------- 目录读取与展开状态 ----------
function! s:MEIsEmptyDir(path) abort
  try
    return empty(readdir(a:path))
  catch
    return 1
  endtry
endfunction

function! s:MEForgetExpanded(path) abort
  if has_key(s:me_expanded, a:path)
    call remove(s:me_expanded, a:path)
  endif
endfunction

" ---------- 图标高亮 ----------
" 图标颜色组 MiniExplorerIcon* 由主题导出，缺失时由 SetupUIHighlights 提供语义链接
function! s:MEIconGroup(color) abort
  let l:color = a:color ==# '' ? 'default' : tolower(a:color)
  return 'MiniExplorerIcon' . substitute(l:color, '\(^\|_\)\zs.', '\u&', 'g')
endfunction

function! s:MEClearIconHighlights() abort
  if !exists('*matchdelete')
    let s:me_icon_matches = []
    return
  endif

  for l:id in s:me_icon_matches
    silent! call matchdelete(l:id)
  endfor

  let s:me_icon_matches = []
endfunction

function! s:MEApplyIconHighlights() abort
  if !exists('*matchaddpos')
    return
  endif

  call s:MEClearIconHighlights()

  let l:lnum = 0
  for l:node in s:me_nodes
    let l:lnum += 1
    let l:hl = get(l:node, 'icon_hl', '')
    let l:col = get(l:node, 'icon_col', 0)
    let l:len = get(l:node, 'icon_len', 0)

    if l:hl ==# '' || l:col <= 0 || l:len <= 0
      continue
    endif

    if !hlexists(l:hl)
      let l:hl = 'MiniExplorerIconDefault'
    endif

    call add(s:me_icon_matches, matchaddpos(l:hl, [[l:lnum, l:col, l:len]], 20))
  endfor
endfunction

" ---------- 文件树渲染 ----------
function! s:MEAddNode(lines, node) abort
  call add(a:lines, a:node.line)
  call add(s:me_nodes, a:node)
endfunction

function! s:MERenderDir(lines, dir, depth) abort
  let l:dirs = []
  let l:files = []

  try
    let l:entries = readdir(a:dir)
  catch
    return
  endtry

  for l:name in l:entries
    let l:path = s:MEPathJoin(a:dir, l:name)
    if isdirectory(l:path)
      call add(l:dirs, l:name)
    else
      call add(l:files, l:name)
    endif
  endfor

  call sort(l:dirs)
  call sort(l:files)

  for l:name in l:dirs
    let l:path = s:MEPathNorm(s:MEPathJoin(a:dir, l:name))
    let l:open = get(s:me_expanded, l:path, 0)
    " 只对已展开的目录读取内容判断是否为空：折叠目录逐个 readdir 在 node_modules 等大目录下很慢
    let l:empty = l:open && s:MEIsEmptyDir(l:path)
    let l:arrow = l:open ? s:me_icons.arrow_open : s:me_icons.arrow_closed
    let l:icon = s:MEDirIcon(l:name, l:open, l:empty)
    let l:indent = repeat('  ', a:depth)
    let l:prefix = l:indent . l:arrow . ' '

    call s:MEAddNode(a:lines, {
      \ 'kind': 'dir',
      \ 'path': l:path,
      \ 'depth': a:depth,
      \ 'line': l:prefix . l:icon.glyph . ' ' . l:name,
      \ 'icon_col': strlen(l:prefix) + 1,
      \ 'icon_len': strlen(l:icon.glyph),
      \ 'icon_hl': s:MEIconGroup(get(l:icon, 'color', '')),
      \ })

    if l:open
      call s:MERenderDir(a:lines, l:path, a:depth + 1)
    endif
  endfor

  for l:name in l:files
    let l:path = s:MEPathNorm(s:MEPathJoin(a:dir, l:name))
    let l:icon = s:MEFileIcon(l:name)
    let l:indent = repeat('  ', a:depth)
    let l:prefix = l:indent . '  '

    call s:MEAddNode(a:lines, {
      \ 'kind': 'file',
      \ 'path': l:path,
      \ 'depth': a:depth,
      \ 'line': l:prefix . l:icon.glyph . ' ' . l:name,
      \ 'icon_col': strlen(l:prefix) + 1,
      \ 'icon_len': strlen(l:icon.glyph),
      \ 'icon_hl': s:MEIconGroup(get(l:icon, 'color', '')),
      \ })
  endfor
endfunction

function! s:MERender(...) abort
  let l:focus_path = a:0 > 0 ? a:1 : ''
  let l:lines = []
  let s:me_nodes = []

  call s:MERenderDir(l:lines, s:me_root, 0)

  if empty(l:lines)
    let l:lines = ['  (empty)']
    let s:me_nodes = [{'kind': 'empty', 'path': '', 'depth': 0, 'line': l:lines[0]}]
  endif

  setlocal modifiable
  " 直接操作 buffer，避免 lazyredraw 下 Ex 模式重复 :delete 时卡住
  call deletebufline(bufnr('%'), 1, '$')
  call setline(1, l:lines)
  setlocal nomodifiable nomodified
  call s:MEApplyIconHighlights()

  if l:focus_path !=# ''
    let l:index = 0
    for l:node in s:me_nodes
      let l:index += 1
      if get(l:node, 'path', '') ==# l:focus_path
        call cursor(l:index, 1)
        return
      endif
    endfor
  endif

  call cursor(min([line('.'), line('$')]), 1)
endfunction

" ---------- 窗口与缓冲区生命周期 ----------
function! s:MEWinId() abort
  if s:me_win > 0 && win_id2win(s:me_win) > 0
    return s:me_win
  endif

  if s:me_buf > 0 && bufexists(s:me_buf)
    for l:winnr in range(1, winnr('$'))
      if winbufnr(l:winnr) == s:me_buf
        let s:me_win = win_getid(l:winnr)
        return s:me_win
      endif
    endfor
  endif

  return 0
endfunction

" buffer 级设置：只在首次创建时执行一次
function! s:MESetupBuffer() abort
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal nobuflisted
  setlocal noswapfile
  setlocal filetype=mini-explorer
  silent! file [MiniExplorer]

  nnoremap <buffer> <silent> q <Cmd>call <SID>MEClose()<CR>
  nnoremap <buffer> <silent> r <Cmd>call <SID>MERefresh()<CR>
  nnoremap <buffer> <silent> h <Cmd>call <SID>MECollapse()<CR>
  nnoremap <buffer> <silent> l <Cmd>call <SID>MEOpenNode()<CR>
  nnoremap <buffer> <silent> <CR> <Cmd>call <SID>MEOpenNode()<CR>

  syntax clear
  syntax match MiniExplorerDir /^\s*[].*$/
endfunction

" 窗口级设置：每次打开新的侧栏窗口都要执行
function! s:MESetupWindow() abort
  setlocal nowrap
  setlocal winfixwidth
  setlocal nonumber
  setlocal norelativenumber
  setlocal signcolumn=no
  setlocal foldcolumn=0
endfunction

function! s:MEOpen(root) abort
  if bufnr('%') != s:me_buf
    let s:me_last_win = win_getid()
  endif

  let s:me_root = s:MEResolveRoot(a:root)

  if s:MEWinId() > 0
    call win_gotoid(s:me_win)
    call s:MERender()
    return
  endif

  " 关闭侧栏只是隐藏 buffer（bufhidden=hide），再次打开时复用，避免泄漏 buffer
  if s:me_buf > 0 && bufexists(s:me_buf)
    topleft vertical 32split
    execute 'silent buffer ' . s:me_buf
  else
    topleft vertical 32new
    let s:me_buf = bufnr('%')
    call s:MESetupBuffer()
  endif
  let s:me_win = win_getid()

  call s:MESetupWindow()
  call s:MERender()
endfunction

function! s:MEClose() abort
  let l:win = s:MEWinId()
  if l:win <= 0
    return
  endif

  call win_gotoid(l:win)
  call s:MEClearIconHighlights()
  if winnr('$') == 1
    " 最后一个窗口不能 :close（E444），换成空 buffer 并恢复普通窗口选项
    enew
    setlocal wrap< nowinfixwidth number< relativenumber< signcolumn< foldcolumn<
  else
    close
  endif
  let s:me_win = -1
endfunction

function! s:METoggle(root) abort
  if s:MEWinId() > 0
    call s:MEClose()
    return
  endif

  call s:MEOpen(a:root)
endfunction

" 与 vv-explorer reveal 一致：侧栏可见就关闭（不论焦点在哪），隐藏时打开并定位当前文件
" 根目录优先 cwd；文件不在其下时以文件所在目录为根，沿途目录全部展开
function! s:MEReveal() abort
  if s:MEWinId() > 0
    call s:MEClose()
    return
  endif

  let l:file = expand('%:p')
  if l:file ==# '' || !filereadable(l:file)
    call s:MEOpen('')
    call cursor(1, 1)
    return
  endif

  let l:file = s:MEPathNorm(l:file)
  let l:root = s:MEPathNorm(getcwd())
  if !s:MEIsUnder(l:file, l:root)
    let l:root = fnamemodify(l:file, ':h')
  endif

  call s:MEOpen(l:root)

  let l:dir = fnamemodify(l:file, ':h')
  while s:MEIsUnder(l:dir, s:me_root)
    let s:me_expanded[l:dir] = 1
    let l:dir = fnamemodify(l:dir, ':h')
  endwhile

  call s:MERender(l:file)
endfunction

" ---------- 文件树动作 ----------
function! s:MECurrentNode() abort
  let l:index = line('.') - 1
  return l:index >= 0 && l:index < len(s:me_nodes)
    \ ? s:me_nodes[l:index]
    \ : {}
endfunction

function! s:MEParentNode(node) abort
  let l:index = line('.') - 2
  while l:index >= 0
    let l:node = s:me_nodes[l:index]
    if get(l:node, 'kind', '') ==# 'dir' && get(l:node, 'depth', 0) < a:node.depth
      return l:node
    endif
    let l:index -= 1
  endwhile

  return {}
endfunction

function! s:MECollapse() abort
  let l:node = s:MECurrentNode()
  if empty(l:node)
    return
  endif

  if l:node.kind ==# 'dir' && get(s:me_expanded, l:node.path, 0)
    call s:MEForgetExpanded(l:node.path)
    call s:MERender(l:node.path)
    return
  endif

  let l:parent = s:MEParentNode(l:node)
  if !empty(l:parent)
    call s:MEForgetExpanded(l:parent.path)
    call s:MERender(l:parent.path)
    return
  endif

  let l:parent_dir = s:MEPathNorm(fnamemodify(s:me_root, ':h'))
  if l:parent_dir !=# s:me_root && isdirectory(l:parent_dir)
    let s:me_root = l:parent_dir
    call s:MERender()
  endif
endfunction

function! s:MERefresh() abort
  let l:node = s:MECurrentNode()
  call s:MERender(get(l:node, 'path', ''))
endfunction

function! s:MEFocusTargetWindow() abort
  let l:tree = s:MEWinId()

  if s:me_last_win > 0
    \ && win_id2win(s:me_last_win) > 0
    \ && s:me_last_win != l:tree
    call win_gotoid(s:me_last_win)
    return
  endif

  for l:winnr in range(1, winnr('$'))
    if winbufnr(l:winnr) != s:me_buf
      execute l:winnr . 'wincmd w'
      let s:me_last_win = win_getid()
      return
    endif
  endfor

  rightbelow vertical new
  let s:me_last_win = win_getid()
endfunction

function! s:MEOpenNode() abort
  let l:node = s:MECurrentNode()
  if empty(l:node)
    return
  endif

  if l:node.kind ==# 'dir'
    let s:me_expanded[l:node.path] = 1
    call s:MERender(l:node.path)
    return
  endif

  if l:node.kind ==# 'file'
    call s:MEFocusTargetWindow()
    execute 'edit ' . fnameescape(l:node.path)
  endif
endfunction

" ---------- 命令与快捷键 ----------
command! -nargs=? -complete=dir MiniExplorer call s:MEOpen(<q-args>)
command! -nargs=? -complete=dir MiniExplorerToggle call s:METoggle(<q-args>)
command! MiniExplorerReveal call s:MEReveal()
" 唯一入口：<Leader>e 关闭已显示的侧栏，或打开并定位当前文件
nnoremap <silent> <Leader>e <Cmd>MiniExplorerReveal<CR>
