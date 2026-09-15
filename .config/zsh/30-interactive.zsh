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

# Keybindings.
# Model: the emacs base (bindkey -e) supplies the load-bearing primitives
# (self-insert, backspace, Enter, Ctrl-A/E, Ctrl-U/K/W, ...). We only layer
# discretionary overrides on top — never clear the keymap: an empty ZLE keymap
# can't even type a letter. Plugins bind their own keys at 10-plugins (before
# this file); those are listed under "plugin-owned" below for reference, not
# re-bound here. To drop a default: bindkey -r '<seq>' (targeted, not a clear).
bindkey -e

# history recall — ↑/↓ prefix-match (text left of cursor filters; empty = all),
# keeping the cursor in place and stepping within a multiline buffer before
# falling through to history. Ctrl-P/N were a redundant second prefix-search →
# unbound in favor of ↑/↓ (re-add here if muscle memory wins).
bindkey -r '^p' '^n'
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search    # ↑  normal cursor mode
bindkey '^[OA' up-line-or-beginning-search    # ↑  application cursor mode
bindkey '^[[B' down-line-or-beginning-search  # ↓  normal
bindkey '^[OB' down-line-or-beginning-search  # ↓  application

# plugin-owned keys (bound by plugins/tools at 10-plugins & 80-tools, not here):
#   Tab            fzf-completion       (fzf-tab)              completion dropdown
#   → / End / C-E  autosuggest-accept   (zsh-autosuggestions)  accept whole suggestion
#   Alt-F          forward-word         (zsh-autosuggestions)  accept one word
#   Ctrl-R         fzf-history-widget   (fzf)                  fuzzy history overlay
#   Ctrl-T         fzf-file-widget      (fzf)                  fuzzy file inserter
#   Alt-C          fzf-cd-widget        (fzf)                  cd into a subdir
#   Esc Esc        sudo-command-line    (OMZP::sudo)           prepend sudo (prev cmd if empty)

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --level=2 --color=always --icons=always --group-directories-first $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --tree --level=2 --color=always --icons=always --group-directories-first $realpath'

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
# _suppress_chpwd: set by gotopr while it bounces through dirs. Initialized here so
# the guard never reads an unset global (and to keep it off until gotopr sets it).
typeset -g _suppress_chpwd=0
chpwd() {
    [[ -o interactive ]] || return
    ((_suppress_chpwd)) || _clear_ls
}

# Guard on a real, reachable tmux server (probed once) — $TMUX can be set with a
# dead/absent server — used by the tmux session helpers (tn/ta/dotslg).
_REAL_TMUX=
[[ -n "$TMUX" ]] && tmux info &>/dev/null && _REAL_TMUX=1
