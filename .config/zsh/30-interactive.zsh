# Disable DEC mode 2031 (color-scheme change notifications) on every prompt.
# Inner apps (claude code, nvim, etc.) enable it and may not clean up; ghostty
# then re-emits \e[?997;Ps n on tmux session-switch, which leaks "997;1n" into
# shell input via tmux's CSI parser.
autoload -Uz add-zsh-hook
_disable_dec_2031() { printf '\e[?2031l'; }
add-zsh-hook precmd _disable_dec_2031

# Disable mouse-tracking modes on every prompt. Inner apps (vim, htop, remote
# tmux over ssh) enable 1000/1002/1003/1006/1015; if they crash or the ssh
# session dies before sending the matching disable, tmux keeps forwarding click
# bytes to the pane and they land as text in the next shell prompt.
_disable_mouse_tracking() { printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l'; }
add-zsh-hook precmd _disable_mouse_tracking

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -G $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls -G $realpath'

# clear screen + ls in one atomic write (no fork for clear, no flash gap)
_clear_ls() {
    local out
    out=$(eza --color=always --icons=always --hyperlink 2>/dev/null)
    printf '\e[H\e[2J\e[3J%s\n' "$out"
}

# Execute on Enter: empty enter → schedule clear+ls for next prompt
_pending_clear_ls=0
accept-line() {
    [[ -z $BUFFER ]] && _pending_clear_ls=1
    zle ".$WIDGET"
}
zle -N accept-line

_run_pending_clear_ls() {
    ((_pending_clear_ls)) || return
    _pending_clear_ls=0
    _clear_ls
}
add-zsh-hook precmd _run_pending_clear_ls

# cd hook: clear+ls on every directory change
# Guard on interactive: Claude Code's Bash tool sources a snapshot that strips
# _-prefixed funcs (drops _clear_ls) but keeps chpwd, then cd's non-interactively
# → "command not found: _clear_ls". The guard is baked into the captured body.
chpwd() {
    [[ -o interactive ]] || return
    ((_suppress_chpwd)) || _clear_ls
}

# herdr sets $TMUX/$TMUX_PANE to impersonate tmux but runs no server, so guard
# on a real server (probed once) — used by the tmux session helpers (tn/ta/dotslg).
_REAL_TMUX=
[[ -n "$TMUX" ]] && tmux info &>/dev/null && _REAL_TMUX=1
