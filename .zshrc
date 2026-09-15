# ~/.zshrc — thin loader. Config is split into ordered modules under
# ~/.config/zsh/ (NN-*.zsh, sourced in numeric order for deterministic load
# order). The session module (mux-tmux.zsh) has no numeric prefix, so this glob
# skips it — 95-session.zsh sources it.
for _f in ~/.config/zsh/[0-9]*.zsh(N); do
    source "$_f"
done
unset _f

# Added by declawd
export PATH="$HOME/.local/bin:$PATH"
