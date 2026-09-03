# Oh My Posh prompt
if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]] && command -v oh-my-posh >/dev/null; then
    eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/zen.toml)"
fi

# Suppress zsh's partial-line end-of-line mark (a reverse-video %). A benign cursor-moving escape emitted
# during startup nudges the cursor off column 0, so PROMPT_SP misfires and prints a spurious % above the
# first prompt in every new pane. Nothing real is being preserved (the "partial line" is invisible), so
# turn the preservation off — the prompt then draws cleanly at column 0.
unsetopt PROMPT_SP
