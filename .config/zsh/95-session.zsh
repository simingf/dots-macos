# Session module: load the herdr- or tmux-specific helpers (kk layout + session
# tools). HERDR_ENV is checked first because herdr fakes $TMUX. Outside herdr we always
# load mux-tmux — its session helpers (tn/ta/tk) use `tmux attach` and work from a plain
# terminal too (so you can attach to existing sessions instead of spawning new ones), and
# kk falls back to claude when not inside tmux.
if [[ "${HERDR_ENV:-}" == 1 ]]; then
    source ~/.config/zsh/mux-herdr.zsh
else
    source ~/.config/zsh/mux-tmux.zsh
fi
