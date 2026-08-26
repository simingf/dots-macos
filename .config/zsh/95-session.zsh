# Session module: load the herdr- or tmux-specific helpers (kk layout + session
# tools) for whichever session this shell is in. HERDR_ENV is checked first because
# herdr fakes $TMUX. A plain base terminal loads neither (kk falls back to claude).
if [[ "${HERDR_ENV:-}" == 1 ]]; then
    source ~/.config/zsh/mux-herdr.zsh
elif [[ -n "${TMUX:-}" ]]; then
    source ~/.config/zsh/mux-tmux.zsh
fi
