# ~/.zshrc — thin loader. Config is split into ordered modules under
# ~/.config/zsh/ (NN-*.zsh, sourced in numeric order for deterministic load
# order). Session modules (mux-herdr.zsh / mux-tmux.zsh) have no numeric prefix,
# so this glob skips them — 95-session.zsh sources the right one conditionally.
for _f in ~/.config/zsh/[0-9]*.zsh(N); do
    source "$_f"
done
unset _f

# Added by declawd
export PATH="$HOME/.local/bin:$PATH"
