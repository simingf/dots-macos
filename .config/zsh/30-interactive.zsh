# --- Terminal-mode resets (every prompt) ---
# Apps that exit/crash without cleanup leave these on; their reports then leak
# into the prompt as text.
autoload -Uz add-zsh-hook
# DEC 2031 (color-scheme reports): ghostty re-emits on session switch → stray 997;1n
_disable_dec_2031() { printf '\e[?2031l'; }
add-zsh-hook precmd _disable_dec_2031

# Mouse tracking (vim, htop, remote tmux over a dead ssh): tmux keeps forwarding clicks
_disable_mouse_tracking() { printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l'; }
add-zsh-hook precmd _disable_mouse_tracking

# --- Keybindings ---
# Layer overrides on the emacs base; never clear the keymap (an empty one can't
# even self-insert) — drop single keys with `bindkey -r`.
bindkey -e

# ↑/↓: prefix-match history (text left of cursor), stepping through multiline
# buffers first. C-p/C-n unbound as redundant.
bindkey -r '^p' '^n'
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search    # ↑  normal cursor mode
bindkey '^[OA' up-line-or-beginning-search    # ↑  application cursor mode
bindkey '^[[B' down-line-or-beginning-search  # ↓  normal
bindkey '^[OB' down-line-or-beginning-search  # ↓  application

# Click-to-move: tmux's MouseUp1Pane stores the click offset in pane option
# @click ("dy dx width cursor_x") and sends \e[9000~. Lays the buffer out as zle
# draws it (wrap at width, newline → column 0) so multi-line buffers work; clicks
# past a row's end clamp, rows outside the buffer are ignored. Single-width chars only.
_click_move() {
    [[ -n $TMUX_PANE ]] || return
    local dy dx w cx reply
    read -r dy dx w cx <<< "$(tmux show -pqv -t "$TMUX_PANE" @click)"
    local -i c0 i row col crow ccol trow tcol first=-1 hit=-1 saved=$CURSOR
    if [[ $LBUFFER != *$'\n'* ]]; then
        (( c0 = ((cx - CURSOR) % w + w) % w ))   # cursor's row is the prompt row: derive from it
    else
        # Ask the terminal where the buffer starts: the report comes back in-band, after the redraw.
        CURSOR=0; zle -R
        print -n '\e[6n' >/dev/tty
        read -rs -t 1 -d R reply </dev/tty
        CURSOR=$saved
        (( c0 = ${reply##*;} - 1 ))
    fi
    local -a rows cols
    (( row = 0, col = c0 ))
    for (( i = 0; i <= $#BUFFER; i++ )); do
        (( col >= w )) && (( row++, col = 0 ))
        rows[i+1]=$row cols[i+1]=$col
        if [[ ${BUFFER[i+1]} == $'\n' ]]; then (( row++, col = 0 )); else (( col++ )); fi
    done
    (( trow = rows[CURSOR+1] + dy, tcol = cols[CURSOR+1] + dx ))
    for (( i = 0; i <= $#BUFFER; i++ )); do
        (( rows[i+1] == trow )) || continue
        (( first < 0 && (first = i) ))
        (( cols[i+1] <= tcol && (hit = i) ))
    done
    (( first < 0 )) && return                      # row outside the buffer
    (( CURSOR = hit < 0 ? first : hit ))
}
zle -N _click_move
bindkey '^[[9000~' _click_move

# GUI-style selection + ⌘ keys: ghostty sends ⌘ keys as \e[90NN~, forwarded by
# scripts/tmux-cmdkey.sh (see KEYBINDS.md). With a selection up, typing/paste/⌫
# replace it; any other key drops it. Copies go out via OSC 52 (works over ssh).
# One function per widget: wrapping plugins rename widgets, so $WIDGET can't dispatch.
_sel_osc52()     { printf '\e]52;c;%s\a' "$(print -rn -- "${BUFFER[MARK+1,CURSOR]}${BUFFER[CURSOR+1,MARK]}" | base64 | tr -d '\n')" > /dev/tty }
_select_all()    { MARK=0; CURSOR=$#BUFFER; REGION_ACTIVE=1 }
_select_left()   { (( REGION_ACTIVE )) || { MARK=$CURSOR; REGION_ACTIVE=1 }; zle .backward-char }
_select_right()  { (( REGION_ACTIVE )) || { MARK=$CURSOR; REGION_ACTIVE=1 }; zle .forward-char }
_bol()           { zle .beginning-of-line; while [[ ${BUFFER[CURSOR+1]} == [[:blank:]] ]]; do (( CURSOR++ )); done }  # first non-blank, like nvim's ^
# ⌘⌫: a selection, else back to the first non-blank — or, from there, the indent
_kill_bol()      { (( REGION_ACTIVE )) && { zle kill-region; return }; local to=$CURSOR; _bol; (( CURSOR >= to )) && zle .beginning-of-line; MARK=$to; zle .kill-region }
_select_bol()    { (( REGION_ACTIVE )) || { MARK=$CURSOR; REGION_ACTIVE=1 }; _bol }
_select_eol()    { (( REGION_ACTIVE )) || { MARK=$CURSOR; REGION_ACTIVE=1 }; zle .end-of-line }
_sel_copy()      { (( REGION_ACTIVE )) && _sel_osc52 }
_sel_cut()       { (( REGION_ACTIVE )) && { _sel_osc52; zle kill-region } }
_sel_insert()    { (( REGION_ACTIVE )) && zle kill-region; zle .self-insert }
_sel_paste()     { (( REGION_ACTIVE )) && zle kill-region; zle .bracketed-paste }
_sel_backspace() { if (( REGION_ACTIVE )); then zle kill-region; else zle .backward-delete-char; fi }
_sel_bkword()    { if (( REGION_ACTIVE )); then zle kill-region; else zle .backward-kill-word; fi }
_sel_drop()      { [[ $LASTWIDGET == (select-all|select-left|select-right|select-bol|select-eol|sel-copy) ]] || REGION_ACTIVE=0 }
zle -N select-all _select_all
zle -N select-left _select_left
zle -N select-right _select_right
zle -N select-bol _select_bol
zle -N smart-bol _bol
zle -N kill-bol _kill_bol
zle -N select-eol _select_eol
zle -N sel-copy _sel_copy
zle -N sel-cut _sel_cut
zle -N self-insert _sel_insert
zle -N bracketed-paste _sel_paste
zle -N backward-delete-char _sel_backspace
zle -N sel-backward-kill-word _sel_bkword
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-pre-redraw _sel_drop
bindkey '^[[9001~' select-all
bindkey '^[[9002~' sel-copy
bindkey '^[[9003~' sel-cut
bindkey '^[[9004~' undo
bindkey '^[[9005~' redo
bindkey '^[[9006~' smart-bol
bindkey '^[[9007~' end-of-line
bindkey '^[[9009~' kill-buffer           # ⇧⌘⌫: delete the whole (multi-line) command
bindkey '^[[9015~' kill-bol              # ⌘⌫: delete back to the first non-blank
bindkey '^[[1;2D' select-left     # ⇧←
bindkey '^[[1;2C' select-right    # ⇧→
bindkey '^[[9016~' select-bol      # ⇧⌘←
bindkey '^[[9017~' select-eol      # ⇧⌘→
bindkey '^[^?' sel-backward-kill-word  # ⌥⌫

# Plugin-owned keys (bound in 10-plugins / 80-tools; reference only):
#   Tab            fzf-completion       (fzf-tab)              completion dropdown
#   → / End / C-E  autosuggest-accept   (zsh-autosuggestions)  accept whole suggestion
#   Alt-F          forward-word         (zsh-autosuggestions)  accept one word
#   Ctrl-R         fzf-history-widget   (fzf)                  fuzzy history overlay
#   Ctrl-T         fzf-file-widget      (fzf)                  fuzzy file inserter
#   Alt-C          fzf-cd-widget        (fzf)                  cd into a subdir
#   Esc Esc        sudo-command-line    (OMZP::sudo)           prepend sudo (prev cmd if empty)

# --- Completion ---
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --level=2 --color=always --icons=always --group-directories-first $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --tree --level=2 --color=always --icons=always --group-directories-first $realpath'

# --- clear + ls (empty Enter, cd) ---
# One atomic write: no flash between clear and ls.
_clear_ls() {
    local out
    out=$(eza --color=always --icons=always --hyperlink 2>/dev/null)
    printf '\e[H\e[2J\e[3J%s\n' "$out"
}

# Empty Enter → clear+ls at the next prompt.
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

# clear+ls on cd. Interactive guard: Claude Code's Bash snapshot keeps chpwd but
# drops _-prefixed funcs. _suppress_chpwd is set by gotopr while it bounces dirs.
typeset -g _suppress_chpwd=0
chpwd() {
    [[ -o interactive ]] || return
    ((_suppress_chpwd)) || _clear_ls
}

# --- tmux ---
# Reachable tmux server ($TMUX can outlive it), probed once; used by tn/ta/*lg.
_REAL_TMUX=
[[ -n "$TMUX" ]] && tmux info &>/dev/null && _REAL_TMUX=1
