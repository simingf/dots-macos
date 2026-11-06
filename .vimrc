" ==========================================================================
" Editor Settings
" ==========================================================================

set nocompatible

" title: show filename; when in tmux, also set the tmux window name
set title
set titlestring=%t
if $TMUX != ''
  let &t_ts = "\<Esc>k"
  let &t_fs = "\<Esc>\\"
endif

" line numbers
set number
set relativenumber
" keep sign column on so text doesn't jump when signs appear
set signcolumn=yes
" highlight current line
set cursorline
" keep N screen lines above and below the cursor
set scrolloff=5
" line wrapping
set wrap
" preserve indentation when line wrapping
set breakindent
" enable mouse for all modes
set mouse=a
" case-insensitive search unless the query has uppercase
set ignorecase
set smartcase
" don't persist highlights of the most recent search
set nohlsearch
" 4-space tabs, expanded to spaces
set tabstop=4
set shiftwidth=4
set expandtab
" show mode in the command line (no lualine here)
set showmode
" true-color support
set termguicolors
" splits open to the right / below
set splitright
set splitbelow

" ==========================================================================
" Key Bindings
" ==========================================================================

let mapleader = " "
let maplocalleader = " "

" window navigation - ctrl w is hard to reach
nnoremap <silent> <leader>w <C-w>

" prevent x / X from modifying the unnamed register
nnoremap x "_x
xnoremap x "_x
nnoremap X "_d
xnoremap X "_d

" yank / paste from the system clipboard
nnoremap gy "+y
xnoremap gy "+y
nnoremap gp "+p

" H / L to move to line start / end, in normal, visual, and operator-pending
noremap <silent> H ^
noremap <silent> L $
