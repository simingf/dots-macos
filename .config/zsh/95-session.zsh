# Session module: load the tmux-specific helpers (kk layout + session tools). Its
# session helpers (tn/ta/tk) use `tmux attach` and work from a plain terminal too (so
# you can attach to existing sessions instead of spawning new ones), and kk falls back
# to claude when not inside tmux.
source ~/.config/zsh/mux-tmux.zsh
