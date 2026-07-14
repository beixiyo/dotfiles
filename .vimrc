" 禁用过时的 vi 兼容模式
set nocompatible

" ================= 插件路径 =================
if isdirectory(expand('~/.config/nvim/vendors/vv-log-hl.nvim'))
  set runtimepath+=~/.config/nvim/vendors/vv-log-hl.nvim
endif

" 加快屏幕刷新，特别是在 Kitty/Ghostty 等现代终端中
set ttyfast
set lazyredraw  " 在执行宏或脚本时不重绘屏幕，提升速度

" 设置编码，防止乱码
set encoding=utf-8
set fileencodings=utf-8,ucs-bom,gb18030,gbk,gb2312,cp936


" ================= 主题色 =================
syntax on
if has("termguicolors")
  " 启用真彩色支持（Kitty/WezTerm/Ghostty 必须开启这个才有漂亮颜色）
  set termguicolors
endif

" 直接加载 tokyonight.nvim 仓库内的 vim 主题文件，避免依赖 ~/.vim/colors 下的软链接
" 主题缺失时回退到内置 desert
let s:theme_file = expand('~/.config/nvim/vendors/tokyonight.nvim/extras/vim/colors/tokyonight-pretty_cat.vim')
if filereadable(s:theme_file)
  execute 'source' fnameescape(s:theme_file)
else
  colorscheme desert
endif
set re=0 " 使用旧的正则表达式引擎，有时能解决渲染错乱


" ================= 光标形状切换 =================
" 插入模式用竖线 (Beam)，普通模式用方块 (Block)
let &t_SI = "\e[5 q" " 竖线
let &t_EI = "\e[1 q" " 方块
let &t_SR = "\e[3 q" " 下划线 (替换模式)
" 启动时立即发送方块光标码——vim 不会因 "进入 Normal" 触发 t_EI
" 故光标会继承 SSH/终端的当前形状（通常是 beam）；t_ti 在接管终端时发送可修复这一问题
let &t_ti .= "\e[1 q"


" ================= 按键 =================
" 快捷键映射
let mapleader = " "
let maplocalleader = "\\"

inoremap jk <Esc>   " 在插入模式下，jk 快速退出到 Normal 模式
" 按 Esc 键清除搜索高亮
nnoremap <silent> <Esc> :noh<CR><Esc>

" 鼠标支持（仅 normal 和 visual 模式，允许点击定位和选中文本）
set mouse=nv


" ================= VSCode 风格快捷键 =================
" 缩短等待时间，避免按 Esc 后产生 ~1s 延迟
set ttimeoutlen=20

" C-s 保存当前文件；C-A-s 保存所有
" 终端若吞掉 C-s（流控），在 shell 中执行 stty -ixon
nnoremap <silent> <C-s> :w<CR>
inoremap <silent> <C-s> <C-o>:w<CR>
xnoremap <silent> <C-s> <Esc>:w<CR>
nnoremap <silent> <C-A-s> :wa<CR>
inoremap <silent> <C-A-s> <C-o>:wa<CR>
xnoremap <silent> <C-A-s> <Esc>:wa<CR>

" Alt + Up/Down 上下移动当前行 / 选中行
nnoremap <silent> <A-Down> :m .+1<CR>==
nnoremap <silent> <A-Up> :m .-2<CR>==
xnoremap <silent> <A-Down> :m '>+1<CR>gv=gv
xnoremap <silent> <A-Up> :m '<-2<CR>gv=gv

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
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [B :bfirst<CR>
nnoremap <silent> ]B :blast<CR>

" C-e / C-y 每次滚动 5 行
nnoremap <C-e> 5<C-e>
nnoremap <C-y> 5<C-y>
xnoremap <C-e> 5<C-e>
xnoremap <C-y> 5<C-y>


" ================= 基本显示设置 =================
set number          " 显示行号
set relativenumber  " 显示相对行号（光标行绝对，其余相对）
set cursorline      " 高亮当前行
" 去掉 CursorLine 的下划线（某些主题/终端会带默认的 cterm=underline），仅保留背景高亮
augroup my_cursorline_no_underline
  autocmd!
  autocmd ColorScheme * hi CursorLine gui=NONE cterm=NONE
augroup END
hi CursorLine gui=NONE cterm=NONE

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


" ================= Statusline =================
set laststatus=2  " 始终显示状态栏
set noshowmode    " 状态栏已显示模式，不再底部重复

let g:sl_mode_map = {
  \ 'n': 'NORMAL', 'no': 'N·OP',
  \ 'v': 'VISUAL', 'V': 'V·LINE', "\<C-v>": 'V·BLOCK',
  \ 's': 'SELECT', 'S': 'S·LINE',
  \ 'i': 'INSERT', 'ic': 'INSERT',
  \ 'R': 'REPLACE', 'Rv': 'V·REPL',
  \ 'c': 'COMMAND', 't': 'TERM',
  \ }

" 每次 statusline 重绘时根据当前模式动态切换高亮色（返回空串不影响显示）
function! SLModeColor()
  let m = mode()
  if m ==# 'i' || m ==# 'ic'
    hi! SLMode guifg=#1a1b26 guibg=#9ece6a ctermfg=0 ctermbg=2
  elseif m =~# '^[vVsS]' || m ==# "\<C-v>"
    hi! SLMode guifg=#1a1b26 guibg=#bb9af7 ctermfg=0 ctermbg=5
  elseif m =~# '^R'
    hi! SLMode guifg=#1a1b26 guibg=#f7768e ctermfg=0 ctermbg=1
  elseif m ==# 'c'
    hi! SLMode guifg=#1a1b26 guibg=#e0af68 ctermfg=0 ctermbg=3
  else
    hi! SLMode guifg=#1a1b26 guibg=#7aa2f7 ctermfg=0 ctermbg=4
  endif
  return ''
endfunction

function! SLMode()
  return get(g:sl_mode_map, mode(), mode())
endfunction

" 缓存 git 分支，切换 buffer / 焦点时刷新，避免每次重绘都调 shell
let g:sl_git = ''
function! SLUpdateGit()
  let out = systemlist('git rev-parse --abbrev-ref HEAD 2>/dev/null')
  let g:sl_git = (!v:shell_error && len(out) && out[0] !=# '') ? '  ' . out[0] . '  ' : ''
endfunction
augroup SLGit
  autocmd!
  autocmd BufEnter,FocusGained * call SLUpdateGit()
augroup END
call SLUpdateGit()

hi! SLMode  guifg=#1a1b26 guibg=#7aa2f7 ctermfg=0 ctermbg=4
hi! SLGit   guifg=#7aa2f7 guibg=NONE    ctermfg=4  ctermbg=NONE
hi! SLFile  guifg=#c0caf5 guibg=NONE    ctermfg=7  ctermbg=NONE
hi! SLMod   guifg=#f7768e guibg=NONE    ctermfg=1  ctermbg=NONE
hi! SLFill  guifg=#565f89 guibg=NONE    ctermfg=8  ctermbg=NONE
hi! SLFt    guifg=#7dcfff guibg=NONE    ctermfg=6  ctermbg=NONE
hi! SLPos   guifg=#c0caf5 guibg=#3b4261 ctermfg=7  ctermbg=8

set statusline=
set statusline+=%{SLModeColor()}%#SLMode#\ %{SLMode()}\ %*
set statusline+=\ %#SLGit#%{g:sl_git}%*
set statusline+=%#SLFile#%f\ %*
set statusline+=%#SLMod#%m%r%*
set statusline+=%#SLFill#%=
set statusline+=%#SLFt#\ %{&filetype}\ %*
set statusline+=%#SLFill#\ %{&fileencoding?&fileencoding:&encoding}\ %*
set statusline+=%#SLPos#\ %l:%c\ %p%%\


" ================= 缩进与 Tab 设置 =================
set tabstop=2       " Tab 显示为 2 空格宽
set shiftwidth=2    " 缩进宽度为 2 空格
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

function! s:DocCommentStar()
  let l:col = col('.') - 1
  let l:line = getline('.')
  let l:before = l:col > 0 ? l:line[:l:col-1] : ''
  let l:after = l:line[l:col:]
  if l:before =~# '/\*$' && l:after !~# '^\s*\*/'
    call setline('.', l:before . '*  */' . l:after)
    call cursor(line('.'), l:col + 3)
  else
    call feedkeys('*', 'n')
  endif
endfunction

function! s:DocCommentEnter()
  let l:col = col('.') - 1
  let l:line = getline('.')
  let l:before = l:col > 0 ? l:line[:l:col-1] : ''
  let l:after = l:line[l:col:]
  if l:before =~# '/\*\*\s*$' && l:after =~# '^\s*\*/'
    let l:indent = matchstr(l:line, '^\s*')
    let l:row = line('.')
    call setline(l:row, substitute(l:before, '\s\+$', '', ''))
    call append(l:row, [l:indent . ' * ', l:indent . ' ' . substitute(l:after, '^\s\+', '', '')])
    call cursor(l:row + 1, len(l:indent) + 4)
  else
    call feedkeys("\<CR>", 'n')
  endif
endfunction

augroup my_doc_comment
  autocmd!
  autocmd FileType javascript,typescript,typescriptreact,javascriptreact,vue,java,c,cpp,css,scss,less,rust,go,php
    \ inoremap <buffer> <silent> * <C-\><C-o>:call <SID>DocCommentStar()<CR>
  autocmd FileType javascript,typescript,typescriptreact,javascriptreact,vue,java,c,cpp,css,scss,less,rust,go,php
    \ inoremap <buffer> <silent> <CR> <C-\><C-o>:call <SID>DocCommentEnter()<CR>
augroup END


" ================= 搜索设置 =================
set ignorecase      " 搜索忽略大小写
set incsearch       " 增量搜索（边输入边匹配）
set hlsearch        " 高亮搜索结果
set smartcase       " 智能大小写（输入大写时才区分大小写）

" j/k 按屏幕行移动（长行 wrap 时体验与 VSCode 一致），带数字前缀时按实际行跳
nnoremap <expr> j v:count == 0 ? 'gj' : 'j'
nnoremap <expr> k v:count == 0 ? 'gk' : 'k'
xnoremap <expr> j v:count == 0 ? 'gj' : 'j'
xnoremap <expr> k v:count == 0 ? 'gk' : 'k'

" Smart 0：首次按跳到首个非空字符（^），已在那里时才到真正行首（0）
" 与 VSCode Home 键行为一致；纯空行时两者相同
function! s:SmartZero()
  let c = col('.')
  normal! ^
  if col('.') == c
    normal! 0
  endif
endfunction
nnoremap <silent> 0 :call <SID>SmartZero()<CR>
xnoremap <silent> 0 :<C-u>call <SID>SmartZero()<CR>

" Y：与 D/C 对齐，复制光标到行尾（修正 Vim 历史遗留的 Y=yy 行为）
nnoremap Y y$

" yy：复制当前行内容，不含前导/尾随空格；需要含缩进用 Vy
nnoremap <silent> yy ^yg_

" 搜索结果居中：按 n 或 N 跳转时，始终让匹配行处于屏幕中间，视线不乱跳
nnoremap n nzz
nnoremap N Nzz
nnoremap * *zz
nnoremap # #zz

" ================= 剪贴板与寄存器终极优化 (适配 WSL/SSH/Mac/Linux) =================
" 1. 黑洞寄存器映射 (解决 x/d/c 等污染问题)
nnoremap <silent> d "_d
nnoremap <silent> D "_D
nnoremap <silent> c "_c
nnoremap <silent> C "_C
nnoremap <silent> x "_x
nnoremap <silent> X "_X

xnoremap <silent> d "_d
xnoremap <silent> D "_D
xnoremap <silent> c "_c
xnoremap <silent> C "_C
xnoremap <silent> x "+x
xnoremap <silent> X "_X

" 2. 跨平台剪贴板整合
if has('wsl') || system('uname -r') =~# 'microsoft'
  " WSL 环境：使用 win32yank 或 clip.exe 同步到 Windows
  let g:clipboard_cmd = 'win32yank.exe'
  if executable(g:clipboard_cmd)
    " 如果安装了 win32yank.exe (Neovim默认推荐方案)
    augroup WSLYank
      autocmd!
      autocmd TextYankPost * if v:event.regname !=# '_' | call system('win32yank.exe -i --crlf', join(v:event.regcontents, "\n")) | endif
    augroup END
    " 因为纯 Vim 在 WSL 中很难真正支持 clipboard=unnamedplus
    " 所以这里覆盖 p 键，让 p 强制从 Windows 剪贴板读取粘贴
    nnoremap <silent> p :let @"=system('win32yank.exe -o --lf')<CR>p
    nnoremap <silent> P :let @"=system('win32yank.exe -o --lf')<CR>P
  else
    " 降级：仅用 clip.exe 复制到 Windows，粘贴请在终端使用 Ctrl+Shift+V
    augroup WSLYank
      autocmd!
      autocmd TextYankPost * if v:event.regname !=# '_' | call system('clip.exe', join(v:event.regcontents, "\n")) | endif
    augroup END
  endif

elseif has('mac') || has('unix')
  " paste 方向：走本地系统剪贴板（wl-paste / pbpaste）
  if has('unnamedplus')
    set clipboard=unnamedplus
  else
    set clipboard=unnamed
  endif

  " copy 方向：无条件同时发 OSC52 + wl-copy（对齐 nvim clipboard.lua 策略）
  "   - 本地：wl-copy 写系统剪贴板，OSC52 冗余无害
  "   - SSH/tmux attach：OSC52 到达当前终端，wl-copy 落宿主机无人读、无害
  "   不在启动时判断 $SSH_TTY，避免持久化 tmux 里被冻结
  function! OSCYank(text)
    let b64 = system('base64 -w0 2>/dev/null || base64', a:text)
    let esc = "\e]52;c;".b64."\x07"
    silent! call system('printf ' . shellescape(esc) . ' > /dev/tty')
  endfunction
  augroup UnixYank
    autocmd!
    autocmd TextYankPost * if v:event.regname !=# '_' | call OSCYank(join(v:event.regcontents, "\n")) | endif
  augroup END
endif

" ================= 可视模式复制与 Yank 闪烁 =================
" 1. 选中模式下按 Ctrl-C 复制到系统剪贴板 (类似 Neovim)
if has('clipboard')
  vnoremap <silent> <C-c> "+y
else
  vnoremap <silent> <C-c> y
endif

" 2. 复制时闪烁视觉反馈 (纯 Vimscript 实现，类似 Neovim 的 on_yank)
if exists('*matchaddpos') && exists('*timer_start')
  function! s:ClearYankHighlight(match_id, win_id, timer_id)
    if win_getid() == a:win_id
      silent! call matchdelete(a:match_id)
    endif
  endfunction

  function! s:FlashYank()
    if v:event.operator !=# 'y' | return | endif
    let l:sl = line("'[")
    let l:el = line("']")
    let l:win_id = win_getid()
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
    let l:match_id = matchaddpos('IncSearch', l:positions)
    call timer_start(200, function('s:ClearYankHighlight', [l:match_id, l:win_id]))
  endfunction

  augroup YankHighlight
    autocmd!
    " 所有的 yank 操作都会触发此闪烁
    autocmd TextYankPost * call s:FlashYank()
  augroup END
endif

" 自动恢复光标位置：重新打开文件时，回到上次关闭时的行
autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif

" sudo 补刀：:W 或 <Leader>W 提权写入
" 原理：
"   1. :w !cmd 走 PTY，sudo 密码提示正常出现
"   2. :w !cmd 中 | 被当作 shell pipe，所以 | setlocal 无法可靠运行
"   3. 用 shell && touch marker 检测是否真正写入成功，再决定是否清 modified 标志
"   4. setlocal nomodified 比 edit! 好：不丢 undo 历史，不重载文件
function! s:SudoWrite() abort
  let l:marker = tempname()
  execute 'write !sudo tee ' . shellescape(expand('%:p')) . ' >/dev/null && touch ' . shellescape(l:marker)
  if filereadable(l:marker)
    call delete(l:marker)
    setlocal nomodified
  else
    echohl ErrorMsg | echom 'SudoWrite: 写入失败或密码错误' | echohl NONE
  endif
endfunction
command! W call s:SudoWrite()
nnoremap <silent> <Leader>W :W<CR>

" 持久化 undo 历史
set undofile

" 多实例编辑同一文件：禁用 swap 消除警告，autoread 保持内容最新
set noswapfile
set autoread
" 启用终端焦点事件上报（让 FocusGained 在终端 vim 中实际触发）
let &t_fe = "\e[?1004h"
let &t_fd = "\e[?1004l"
autocmd FocusGained,BufEnter * checktime


" ================= Mini Explorer（纯 Vimscript 文件树） =================
" 目标：
"   1. 单文件 .vimrc 可分发，服务器上无需安装 nvim / 插件
"   2. 只做文件树概念：显示、展开、折叠、打开文件
"   3. 若检测到 vv-icons.nvim 的 JSON 数据，则复用目录 / 文件图标；否则降级为纯文本符号

let s:me_buf = -1
let s:me_win = -1
let s:me_last_win = -1
let s:me_root = ''
let s:me_nodes = []
let s:me_expanded = {}

let s:me_icons = {
  \ 'arrow_closed': '▸',
  \ 'arrow_open': '▾',
  \ 'folder': {'glyph': '[D]', 'color': ''},
  \ 'folder_open': {'glyph': '[D]', 'color': ''},
  \ 'folder_empty': {'glyph': '[D]', 'color': ''},
  \ 'file': {'glyph': '[F]', 'color': ''},
  \ }

let s:me_file_icons = {}
let s:me_dir_icons = {}
let s:me_ext_icons = {}
let s:me_icon_matches = []

" ---------- path helpers ----------
function! s:MEPathNorm(path) abort
  let l:path = fnamemodify(a:path, ':p')
  let l:path = substitute(l:path, '[\/]\+$', '', '')
  return l:path ==# '' ? '/' : l:path
endfunction

function! s:MEPathJoin(dir, name) abort
  return a:dir =~# '[\/]$' ? a:dir . a:name : a:dir . '/' . a:name
endfunction

function! s:MEResolveRoot(path) abort
  let l:raw = a:path ==# '' ? getcwd() : expand(a:path)

  if filereadable(l:raw)
    let l:raw = fnamemodify(l:raw, ':h')
  endif

  let l:root = s:MEPathNorm(l:raw)
  return isdirectory(l:root) ? l:root : s:MEPathNorm(getcwd())
endfunction

" ---------- vv-icons optional loader ----------
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

" ---------- filesystem helpers ----------
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

" ---------- highlights ----------
function! s:MEIconGroup(color) abort
  let l:color = a:color ==# '' ? 'default' : tolower(a:color)
  return 'MiniExplorerIcon' . substitute(l:color, '\(^\|_\)\zs.', '\u&', 'g')
endfunction

function! s:MEDefineIconHighlights() abort
  highlight default MiniExplorerIconDefault guifg=#c0caf5 ctermfg=7
  highlight default MiniExplorerIconBlue    guifg=#7aa2f7 ctermfg=4
  highlight default MiniExplorerIconCyan    guifg=#7dcfff ctermfg=6
  highlight default MiniExplorerIconGreen   guifg=#9ece6a ctermfg=2
  highlight default MiniExplorerIconYellow  guifg=#e0af68 ctermfg=3
  highlight default MiniExplorerIconOrange  guifg=#ff9e64 ctermfg=3
  highlight default MiniExplorerIconRed     guifg=#f7768e ctermfg=1
  highlight default MiniExplorerIconPurple  guifg=#bb9af7 ctermfg=5
  highlight default MiniExplorerIconMagenta guifg=#bb9af7 ctermfg=5
  highlight default MiniExplorerIconGrey    guifg=#565f89 ctermfg=8
  highlight default MiniExplorerIconGray    guifg=#565f89 ctermfg=8
  highlight default MiniExplorerIconWhite   guifg=#c0caf5 ctermfg=7
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

" ---------- render ----------
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
    let l:empty = s:MEIsEmptyDir(l:path)
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
  silent! %delete _
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

" ---------- window / buffer ----------
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

function! s:MESetupBuffer() abort
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal nobuflisted
  setlocal noswapfile
  setlocal nowrap
  setlocal winfixwidth
  setlocal nonumber
  setlocal norelativenumber
  setlocal signcolumn=no
  setlocal foldcolumn=0
  setlocal filetype=mini-explorer
  silent! file [MiniExplorer]

  nnoremap <buffer> <silent> q :call <SID>MEClose()<CR>
  nnoremap <buffer> <silent> r :call <SID>MERefresh()<CR>
  nnoremap <buffer> <silent> h :call <SID>MECollapse()<CR>
  nnoremap <buffer> <silent> l :call <SID>MEOpenNode()<CR>
  nnoremap <buffer> <silent> <CR> :call <SID>MEOpenNode()<CR>

  syntax clear
  syntax match MiniExplorerDir /^\s*[▸▾].*$/

  call s:MEDefineIconHighlights()

  highlight default link MiniExplorerDir Directory
  highlight default link MiniExplorerFile Normal
endfunction

function! s:MEOpen(root) abort
  if bufname('%') !=# '[MiniExplorer]'
    let s:me_last_win = win_getid()
  endif

  let s:me_root = s:MEResolveRoot(a:root)

  if s:MEWinId() > 0
    call win_gotoid(s:me_win)
    call s:MERender()
    return
  endif

  topleft vertical 32new
  let s:me_buf = bufnr('%')
  let s:me_win = win_getid()

  call s:MESetupBuffer()
  call s:MERender()
endfunction

function! s:MEClose() abort
  let l:win = s:MEWinId()
  if l:win <= 0
    return
  endif

  call win_gotoid(l:win)
  call s:MEClearIconHighlights()
  close
  let s:me_win = -1
endfunction

function! s:METoggle(root) abort
  if s:MEWinId() > 0
    call s:MEClose()
    return
  endif

  call s:MEOpen(a:root)
endfunction

" ---------- actions ----------
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

command! -nargs=? -complete=dir MiniExplorer call s:MEOpen(<q-args>)
command! -nargs=? -complete=dir MiniExplorerToggle call s:METoggle(<q-args>)
nnoremap <silent> <Leader>e :MiniExplorerToggle<CR>
