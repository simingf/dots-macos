# Prompt — oh-my-posh with the shared zen.toml (linux runs the vendored binary).
# Apple Terminal can't render it, so it gets the fallback; so does a box where
# the binary isn't present yet (fresh pull before setup.sh links it, non-x86_64).
if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]] && command -v oh-my-posh >/dev/null; then
    eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/zen.toml)"
else
    autoload -Uz vcs_info
    precmd() { vcs_info; }
    zstyle ':vcs_info:git:*' formats '(%b)'
    setopt PROMPT_SUBST
    PROMPT='zsh|%F{#ceacf6}%~%f%F{yellow}${vcs_info_msg_0_}%f%F{#ceacf6}>%f '
fi

# Suppress zsh's partial-line end-of-line mark (a reverse-video %). A benign cursor-moving escape emitted
# during startup nudges the cursor off column 0, so PROMPT_SP misfires and prints a spurious % above the
# first prompt in every new pane. Nothing real is being preserved (the "partial line" is invisible), so
# turn the preservation off — the prompt then draws cleanly at column 0.
unsetopt PROMPT_SP
