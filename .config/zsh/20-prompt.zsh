# oh-my-posh (shared zen.toml); vcs_info fallback for Apple Terminal (can't
# render it) or when the binary is missing.
if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]] && command -v oh-my-posh >/dev/null; then
    eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/zen.toml)"
else
    autoload -Uz vcs_info
    precmd() { vcs_info; }
    zstyle ':vcs_info:git:*' formats '(%b)'
    setopt PROMPT_SUBST
    PROMPT='zsh|%F{#ceacf6}%~%f%F{yellow}${vcs_info_msg_0_}%f%F{#ceacf6}>%f '
fi

# A startup escape nudges the cursor off column 0, so PROMPT_SP would print a
# spurious reverse-video % above the first prompt in every new pane.
unsetopt PROMPT_SP
