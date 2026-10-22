" 可选全局 bufferline：在 tabline 列出 listed buffer，高亮当前项，显示修改标记，同名补父目录，窄屏围绕当前项截断
" ~/.vimrc 显式导入；单独复制本文件也可 source，不依赖 Neovim 或其他模块
" g:vim_bufferline 可配置 max_name_width（@default 28）、colors（@default 同 nvim vv-bufferline spec 的 palette 取色）
" 切换沿用原生 :bnext / :bprevious 等；鼠标点击标签切换 buffer（仅 Normal 模式，需 'mouse' 含 n）
" Vim 的 tabline 没有自定义点击回调，点击靠映射 <LeftMouse> + getmousepos() 按渲染时记录的列区间命中
" 多个 tab 页时右侧显示「当前/总数」，替代被顶掉的原生 tab 页标签
scriptencoding utf-8
let s:user_opts = get(g:, 'vim_bufferline', {})
let s:opts = extend({'max_name_width': 28}, s:user_opts)
let s:opts.colors = extend({
  \ 'fill_bg': '#181825',
  \ 'inactive_bg': '#1e1e2e',
  \ 'active_bg': '#334d70',
  \ 'inactive_fg': '#a8a8a8',
  \ 'active_fg': '#ffffff',
  \ 'muted_fg': '#7f848e',
  \ 'modified_fg': '#e5c07b',
  \ }, get(s:user_opts, 'colors', {}))
" 最近一次渲染的标签屏幕列区间：[{'start', 'end', 'buf'}]，供点击命中
let s:hits = []

" 真彩下使用 colors 取色；非真彩无法显示 gui 色，链接到标准 TabLine 组
" ColorScheme 后重新设置，避免 hi clear 清掉自定义组
function! s:SetupHighlights() abort
  if !has('gui_running') && !(has('termguicolors') && &termguicolors)
    hi default link VimBufferlineFill TabLineFill
    hi default link VimBufferlineTrunc TabLineFill
    hi default link VimBufferlineInactive TabLine
    hi default link VimBufferlineInactiveModified TabLine
    hi default link VimBufferlineCurrent TabLineSel
    hi default link VimBufferlineCurrentModified TabLineSel
    return
  endif

  let l:c = s:opts.colors
  execute printf('hi VimBufferlineFill guibg=%s guifg=%s', l:c.fill_bg, l:c.inactive_fg)
  execute printf('hi VimBufferlineTrunc guibg=%s guifg=%s', l:c.fill_bg, l:c.muted_fg)
  execute printf('hi VimBufferlineInactive guibg=%s guifg=%s', l:c.inactive_bg, l:c.inactive_fg)
  execute printf('hi VimBufferlineInactiveModified guibg=%s guifg=%s', l:c.inactive_bg, l:c.modified_fg)
  execute printf('hi VimBufferlineCurrent guibg=%s guifg=%s gui=bold', l:c.active_bg, l:c.active_fg)
  execute printf('hi VimBufferlineCurrentModified guibg=%s guifg=%s gui=bold', l:c.active_bg, l:c.modified_fg)
endfunction

" 可显示的 buffer：listed 且为普通文件 buffer（排除 help / quickfix / terminal 等）
function! s:Buffers() abort
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&buftype") ==# ""')
endfunction

" 生成每个 buffer 的显示名；文件名重复时补一级父目录区分，超长按 max_name_width 截断
function! s:Labels(bufs) abort
  let l:tails = map(copy(a:bufs), 'fnamemodify(bufname(v:val), ":t")')
  let l:labels = []

  for l:i in range(len(a:bufs))
    let l:tail = l:tails[l:i]
    if l:tail ==# ''
      let l:label = '[No Name]'
    elseif count(l:tails, l:tail) > 1
      let l:label = fnamemodify(bufname(a:bufs[l:i]), ':p:h:t') . '/' . l:tail
    else
      let l:label = l:tail
    endif

    if strchars(l:label) > s:opts.max_name_width
      let l:label = strcharpart(l:label, 0, s:opts.max_name_width - 1) . '…'
    endif
    call add(l:labels, l:label)
  endfor

  return l:labels
endfunction

" 'tabline' 以 %! 求值，每次重绘自动刷新，无需 autocmd 维护状态
function! s:Render() abort
  let l:bufs = s:Buffers()
  let l:labels = s:Labels(l:bufs)
  let l:mods = map(copy(l:bufs), 'getbufvar(v:val, "&modified")')
  " 每项为「 名称 」或「 名称 ● 」，● 单独着色
  let l:widths = map(copy(l:labels), 'strdisplaywidth(v:val) + 2 + (l:mods[v:key] ? 2 : 0)')
  let l:tabs = tabpagenr('$') > 1 ? printf(' %d/%d ', tabpagenr(), tabpagenr('$')) : ''

  " 从当前项向两侧扩展直到放不下；预留两端 < > 标记各 1 列
  let l:avail = &columns - strdisplaywidth(l:tabs) - 2
  let l:cur = max([index(l:bufs, bufnr('%')), 0])
  let [l:first, l:last] = [l:cur, l:cur]
  let l:used = empty(l:bufs) ? 0 : l:widths[l:cur]
  let l:grew = !empty(l:bufs)
  while l:grew
    let l:grew = 0
    if l:last + 1 < len(l:bufs) && l:used + l:widths[l:last + 1] <= l:avail
      let l:last += 1
      let l:used += l:widths[l:last]
      let l:grew = 1
    endif
    if l:first > 0 && l:used + l:widths[l:first - 1] <= l:avail
      let l:first -= 1
      let l:used += l:widths[l:first]
      let l:grew = 1
    endif
  endwhile

  let l:line = '%#VimBufferlineTrunc#' . (l:first > 0 ? '<' : '')
  let l:col = l:first > 0 ? 2 : 1
  let s:hits = []
  for l:i in empty(l:bufs) ? [] : range(l:first, l:last)
    let l:group = l:bufs[l:i] == bufnr('%') ? 'VimBufferlineCurrent' : 'VimBufferlineInactive'
    let l:line .= '%#' . l:group . '# ' . substitute(l:labels[l:i], '%', '%%', 'g') . ' '
    if l:mods[l:i]
      let l:line .= '%#' . l:group . 'Modified#● '
    endif
    call add(s:hits, {'start': l:col, 'end': l:col + l:widths[l:i] - 1, 'buf': l:bufs[l:i]})
    let l:col += l:widths[l:i]
  endfor
  let l:line .= '%#VimBufferlineTrunc#' . (l:last + 1 < len(l:bufs) ? '>' : '')

  return l:line . '%#VimBufferlineFill#%=%#VimBufferlineInactive#' . l:tabs
endfunction

" 点击分两步：按下只记录命中的 buffer，松开时再切换；其他位置原样交还 Vim 默认处理
" 按下即切换时，同一次点击的松开序列会以原始字符残留在命令行
let s:pressed = 0

function! s:Press() abort
  let l:pos = getmousepos()
  let s:pressed = 0
  if l:pos.screenrow == 1 && l:pos.winid == 0
    for l:hit in s:hits
      if l:pos.screencol >= l:hit.start && l:pos.screencol <= l:hit.end
        let s:pressed = l:hit.buf
        return ''
      endif
    endfor
  endif
  return "\<LeftMouse>"
endfunction

function! s:Release() abort
  if !s:pressed
    return "\<LeftRelease>"
  endif
  let l:buf = s:pressed
  let s:pressed = 0
  " 拖离 tabline 再松开视为取消
  return getmousepos().screenrow == 1 ? printf("\<Cmd>buffer %d\<CR>", l:buf) : ''
endfunction

call s:SetupHighlights()
augroup VimBufferline
  autocmd!
  autocmd ColorScheme * call s:SetupHighlights()
augroup END

set showtabline=2
nnoremap <silent> <expr> <LeftMouse> <SID>Press()
nnoremap <silent> <expr> <LeftRelease> <SID>Release()
let &tabline = '%!' . expand('<SID>') . 'Render()'
