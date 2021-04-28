" *************************************************
" * Preamble
" *************************************************

if get(g:, 'loaded_scrollview', 0)
  finish
endif
let g:loaded_scrollview = 1

let s:save_cpo = &cpo
set cpo&vim

" The additional check for ##WinScrolled may be redundant, but was added in
" case early versions of nvim 0.5 didn't have that event.
if !has('nvim-0.5') || !exists('##WinScrolled')
  " Logging error with echomsg or echoerr interrupts Neovim's startup by
  " blocking. Fail silently.
  finish
endif

" *************************************************
" * User Configuration
" *************************************************

let g:scrollview_on_startup = get(g:, 'scrollview_on_startup', 1)
let g:scrollview_mode = get(g:, 'scrollview_mode', 'virtual')
let g:scrollview_excluded_filetypes = 
      \ get(g:, 'scrollview_excluded_filetypes', [])
let g:scrollview_current_only = get(g:, 'scrollview_current_only', 0)
" The default highlight group is specified below.
" Change this default by defining or linking an alternative highlight group.
" E.g., the following will use the Pmenu highlight.
"   :highlight link ScrollView Pmenu
" E.g., the following will use custom highlight colors.
"   :highlight ScrollView ctermbg=159 guibg=LightCyan
highlight default link ScrollView Visual
" Using a winblend of 100 results in the bar becoming invisible on nvim-qt.
let g:scrollview_winblend = get(g:, 'scrollview_winblend', 50)
let g:scrollview_column = get(g:, 'scrollview_column', 2)
let g:scrollview_base = get(g:, 'scrollview_base', 'right')
let g:scrollview_auto_mouse = get(g:, 'scrollview_auto_mouse', 1)
let g:scrollview_auto_workarounds = get(g:, 'scrollview_auto_workarounds', 1)
let g:scrollview_nvim_14040_workaround =
      \ get(g:, 'scrollview_nvim_14040_workaround', 0)
let g:scrollview_refresh_time = get(g:, 'scrollview_refresh_time', 100)
let g:scrollview_character = get(g:, 'scrollview_character', '')

" *************************************************
" * Global State
" *************************************************

" External global state that can be modified by the user is specified here.
" Internal global state is represented with local variables in
" autoload/scrollview.vim and lua/scrollview.lua.

" A flag that gets set to true if the time to refresh scrollbars exceeded
" g:scrollview_refresh_time.
let g:scrollview_refresh_time_exceeded =
      \ get(g:, 'scrollview_refresh_time_exceeded', 0)

" *************************************************
" * Commands
" *************************************************

if !exists(':ScrollViewRefresh')
  command -bar ScrollViewRefresh :call scrollview#ScrollViewRefresh()
endif

if !exists(':ScrollViewEnable')
  command -bar ScrollViewEnable :call scrollview#ScrollViewEnable()
endif

if !exists(':ScrollViewDisable')
  command -bar ScrollViewDisable :call scrollview#ScrollViewDisable()
endif

" *************************************************
" * Mappings
" *************************************************

" <plug> mappings for mouse functionality.
" E.g., <plug>(ScrollViewLeftMouse)
let s:mouse_plug_pairs = [
      \   ['ScrollViewLeftMouse',   'left'  ],
      \   ['ScrollViewMiddleMouse', 'middle'],
      \   ['ScrollViewRightMouse',  'right' ],
      \   ['ScrollViewX1Mouse',     'x1'    ],
      \   ['ScrollViewX2Mouse',     'x2'    ],
      \ ]
for [s:plug_name, s:button] in s:mouse_plug_pairs
  let s:lhs = printf('<silent> <plug>(%s)', s:plug_name)
  let s:rhs = printf('<cmd>call scrollview#HandleMouse("%s")<cr>', s:button)
  execute 'noremap' s:lhs s:rhs
  execute 'inoremap' s:lhs s:rhs
endfor

if g:scrollview_auto_mouse
  " Create a <leftmouse> mapping only if one does not already exist.
  " For example, a mapping may already exist if the user uses swapped buttons
  " from $VIMRUNTIME/pack/dist/opt/swapmouse/plugin/swapmouse.vim. Handling
  " for that scenario would require modifications (e.g., possibly by updating
  " the non-initial feedkeys calls in scrollview#HandleMouse to remap keys).
  silent! nmap <unique> <silent> <leftmouse> <plug>(ScrollViewLeftMouse)
  silent! vmap <unique> <silent> <leftmouse> <plug>(ScrollViewLeftMouse)
  silent! imap <unique> <silent> <leftmouse> <plug>(ScrollViewLeftMouse)
endif

" Additional <plug> mappings are defined for convenience of creating
" user-defined mappings that call nvim-scrollview functionality. However,
" since the usage of <plug> mappings requires recursive map commands, this
" prevents mappings that both call <plug> functions and have the
" left-hand-side key sequences repeated not at the beginning of the
" right-hand-side (see :help recursive_mapping for details). Experimentation
" suggests <silent> is not necessary for <cmd> mappings, but it's added to
" make it explicit.
noremap  <silent> <plug>(ScrollViewDisable) <cmd>ScrollViewDisable<cr>
inoremap <silent> <plug>(ScrollViewDisable) <cmd>ScrollViewDisable<cr>
noremap  <silent> <plug>(ScrollViewEnable)  <cmd>ScrollViewEnable<cr>
inoremap <silent> <plug>(ScrollViewEnable)  <cmd>ScrollViewEnable<cr>
noremap  <silent> <plug>(ScrollViewRefresh) <cmd>ScrollViewRefresh<cr>
inoremap <silent> <plug>(ScrollViewRefresh) <cmd>ScrollViewRefresh<cr>

" Creates a mapping where the left-hand-side key sequence is repeated on the
" right-hand-side, followed by a scrollview refresh. 'modes' is a string with
" each character specifying a mode (e.g., 'nvi' for normal, visual, and insert
" modes). 'seq' is the key sequence that will be remapped. Existing mappings
" are not clobbered.
function s:CreateRefreshMapping(modes, seq) abort
  for l:idx in range(strchars(a:modes))
    let l:mode = strcharpart(a:modes, l:idx, 1)
    execute printf(
          \ 'silent! %smap <unique> %s %s<plug>(ScrollViewRefresh)',
          \ l:mode, a:seq, a:seq)
  endfor
endfunction

" An 'operatorfunc' for g@ that executes zf and then refreshes scrollbars.
function! s:ZfOperator(type) abort
  " Handling for 'char' is needed since e.g., using linewise mark jumping
  " results in the cursor moving to the beginning of the line for zfl, which
  " should not move the cursor. Separate handling for 'line' is needed since
  " e.g., with 'char' handling, zfG won't include the last line in the fold if
  " the cursor gets positioned on the first character.
  if a:type ==# 'char'
    silent normal! `[zf`]
  elseif a:type ==# 'line'
    silent normal! '[zf']
  else
    " Unsupported
  endif
  ScrollViewRefresh
endfunction

if g:scrollview_auto_workarounds
  " === Window arrangement synchronization workarounds ===
  let s:win_seqs = [
        \   '<c-w>H', '<c-w>J', '<c-w>K', '<c-w>L',
        \   '<c-w>r', '<c-w><c-r>', '<c-w>R'
        \ ]
  for s:seq in s:win_seqs
    call s:CreateRefreshMapping('nv', s:seq)
  endfor
  " === Mouse wheel scrolling syncronization workarounds ===
  let s:wheel_seqs = ['<scrollwheelup>', '<scrollwheeldown>']
  for s:seq in s:wheel_seqs
    call s:CreateRefreshMapping('nvi', s:seq)
  endfor
  " === Fold command synchronization workarounds ===
  " zf takes a motion in normal mode, so it requires a g@ mapping.
  silent! nnoremap <unique> zf <cmd>set operatorfunc=<sid>ZfOperator<cr>g@
  call s:CreateRefreshMapping('v', 'zf')
  let s:fold_seqs = [
        \   'zF', 'zd', 'zD', 'zE', 'zo', 'zO', 'zc', 'zC', 'za', 'zA', 'zv',
        \   'zx', 'zX', 'zm', 'zM', 'zr', 'zR', 'zn', 'zN', 'zi'
        \ ]
  for s:seq in s:fold_seqs
    call s:CreateRefreshMapping('nv', s:seq)
  endfor
  " === <c-w>c for the tab last window workaround ===
  " A workaround is intentionally not currently applied. It would need careful
  " handling to 1) ensure that if scrollview had been disabled, it doesn't get
  " re-enabled, and 2) avoid flickering (possibly by only disabling/enabling
  " when there is a single ordinary window in the tab, as the workaround would
  " not be needed otherwise).
endif

" *************************************************
" * Core
" *************************************************

if g:scrollview_on_startup
  " Enable scrollview asynchronously. This avoids an issue that prevents diff
  " mode from functioning properly when it's launched at startup (i.e., with
  " nvim -d). The issue is reported in Neovim Issue #13720.
  call timer_start(0, {-> execute('call scrollview#ScrollViewEnable()')})
endif

" *************************************************
" * Postamble
" *************************************************

let &cpo = s:save_cpo
unlet s:save_cpo
