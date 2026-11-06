# Thin loader: source ~/.config/zsh/NN-*.zsh in numeric order.
# mux-tmux.zsh has no prefix, so it's skipped here (95-session.zsh sources it).
for _f in ~/.config/zsh/[0-9]*.zsh(N); do
    source "$_f"
done
unset _f
