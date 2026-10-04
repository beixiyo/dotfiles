" 可选分栏增强：Ctrl+Alt+hjkl 导航，Ctrl+Alt+方向键移动分隔线；仅支持 Vim / tmux
" ~/.vimrc 显式导入；单独复制本文件也可 source，不依赖 Neovim 或其他模块
" g:vim_smart_splits 可配置 amount（@default 3）、tmux（@default 1）
" tmux 路由使用当前前台 Vim 的 PID 能力声明，不会仅凭历史 pane 标记判断编辑器
scriptencoding utf-8
let s:opts = extend({'amount': 3, 'tmux': 1}, get(g:, 'vim_smart_splits', {}))

" tmux 下启用扩展键；保留主配置设置的光标启动码与 RGB 转义码
if exists('+keyprotocol') && $TMUX !=# '' && &term =~# 'tmux\|screen'
  if &keyprotocol !~# 'tmux:mok2'
    let &keyprotocol .= ',tmux:mok2,screen:mok2'
  endif
  let s:term_codes = [&t_ti, &t_8f, &t_8b]
  let &term = &term
  let [&t_ti, &t_8f, &t_8b] = s:term_codes
  unlet s:term_codes
endif

let s:directions = {
  \ 'h': {'flag': 'L', 'edge': 'left'},
  \ 'j': {'flag': 'D', 'edge': 'bottom'},
  \ 'k': {'flag': 'U', 'edge': 'top'},
  \ 'l': {'flag': 'R', 'edge': 'right'},
  \ }

" 执行显式 socket / pane 的 tmux 命令；缺失依赖或命令失败时返回失败，不报启动错误
function! s:TmuxCommand(args) abort
  let l:socket = matchstr($TMUX, '^.\+\ze,\d\+,\d\+$')
  if !s:opts.tmux || l:socket ==# '' || $TMUX_PANE ==# '' || !executable('tmux')
    return {'ok': 0, 'output': ''}
  endif
  let l:command = ['tmux', '-S', l:socket] + a:args
  let l:output = system(join(map(l:command, 'shellescape(v:val)'), ' '))
  return {'ok': v:shell_error == 0, 'output': trim(l:output)}
endfunction

" 声明本进程具有导航映射；嵌套终端里的 Vim 不能抢占外层 Vim 的 pane 声明
function! s:AdvertiseTmuxNavigation() abort
  if !exists('+keyprotocol') || !has('ttyin') || !has('ttyout')
    return
  endif
  let l:pane = s:TmuxCommand(['display-message', '-p', '-t', $TMUX_PANE, '#{pane_tty}'])
  if !l:pane.ok
    return
  endif
  let l:tty = trim(system('ps -o tty= -p ' . getpid()))
  if v:shell_error != 0 || l:tty !=# substitute(l:pane.output, '^/dev/', '', '')
    return
  endif
  call s:TmuxCommand(['set-option', '-p', '-t', $TMUX_PANE, '@vim_smart_splits_pid', string(getpid())])
endfunction

" 幂等释放自己拥有的声明；不删除另一个进程后写入的声明
function! s:ClearTmuxNavigation() abort
  let l:owner = s:TmuxCommand(['display-message', '-p', '-t', $TMUX_PANE, '#{@vim_smart_splits_pid}'])
  if l:owner.ok && l:owner.output ==# string(getpid())
    call s:TmuxCommand(['set-option', '-pu', '-t', $TMUX_PANE, '@vim_smart_splits_pid'])
  endif
endfunction

" 内部没有邻窗 / 分隔线时委托 tmux；缩放模式及外侧边缘禁止导航绕回
function! s:TmuxAction(action, direction) abort
  let l:dir = s:directions[a:direction]
  let l:format = '#{@vim_smart_splits_pid} #{window_zoomed_flag} #{pane_at_' . l:dir.edge . '}'
  let l:state = s:TmuxCommand(['display-message', '-p', '-t', $TMUX_PANE, l:format])
  let l:values = split(l:state.output)
  if !l:state.ok || len(l:values) != 3 || l:values[0] !=# string(getpid()) || l:values[1] ==# '1'
    return 0
  endif
  if a:action ==# 'move'
    if l:values[2] ==# '1'
      return 0
    endif
    let l:args = ['select-pane', '-t', $TMUX_PANE, '-' . l:dir.flag]
  else
    let l:args = ['resize-pane', '-t', $TMUX_PANE, '-' . l:dir.flag, string(s:opts.amount)]
  endif
  return s:TmuxCommand(l:args).ok
endfunction

" 优先切换 Vim 内部邻窗；边缘时交给 tmux，不制造临时窗口焦点切换
function! s:Move(direction) abort
  if winnr(a:direction) != winnr()
    execute 'wincmd ' . a:direction
    return 1
  endif
  return s:TmuxAction('move', a:direction)
endfunction

" 同 vv-splits：优先移动自己的右 / 下边界，轴上最后一窗改为左 / 上边界
" 本地边界存在但受最小尺寸限制时停止，不能误缩放外部 pane
function! s:Resize(direction) abort
  let l:horizontal = a:direction ==# 'h' || a:direction ==# 'l'
  let l:next = winnr(l:horizontal ? 'l' : 'j')
  let l:previous = winnr(l:horizontal ? 'h' : 'k')
  let l:current = winnr()
  if l:next == l:current && l:previous == l:current
    return s:TmuxAction('resize', a:direction)
  endif
  let l:owner = l:next != l:current ? l:current : l:previous
  let l:offset = s:opts.amount * (a:direction ==# 'l' || a:direction ==# 'j' ? 1 : -1)
  let l:before = winrestcmd()
  if l:horizontal
    call win_move_separator(l:owner, l:offset)
  else
    call win_move_statusline(l:owner, l:offset)
  endif
  return winrestcmd() !=# l:before
endfunction

" 与 Neovim 配置一致，只绑定普通模式和终端任务模式，保留插入 / 可视模式行为
for [s:key, s:direction] in [['h', 'h'], ['j', 'j'], ['k', 'k'], ['l', 'l'],
  \ ['Left', 'h'], ['Down', 'j'], ['Up', 'k'], ['Right', 'l']]
  let s:action = s:key =~# '^\u' ? 'Resize' : 'Move'
  for s:mode in ['n', 't']
    execute s:mode . 'noremap <silent> <C-A-' . s:key . '> <Cmd>call <SID>' . s:action . '("' . s:direction . '")<CR>'
  endfor
endfor
unlet s:key s:direction s:action s:mode

augroup vim_smart_splits
  autocmd!
  autocmd VimEnter * call s:AdvertiseTmuxNavigation()
  autocmd VimLeavePre * call s:ClearTmuxNavigation()
augroup END
if v:vim_did_enter
  call s:AdvertiseTmuxNavigation()
endif
