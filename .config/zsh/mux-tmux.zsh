# tmux module (sourced by 95-session.zsh): kk layout + session helpers.
# Uses claude() / _REAL_TMUX from the numbered modules. Byte-identical: no host paths.

# _kk_stay <cmd>: pane command that drops to a shell when <cmd> exits (instead of closing
# the pane). `zsh -il -c`, not tmux's `sh -c`: sh won't give <cmd> the foreground tty
# when another command follows it.
_kk_stay() {
    local inner="$1; exec zsh -il"
    print -r -- "exec zsh -il -c ${(q)inner}"
}

# kk: nvim 50% | claude 50% (claude in the origin pane). Args: -flags → claude; existing
# paths → nvim (default: git root or $PWD); anything else → claude prompt.
# Quitting either tool leaves a shell. Outside tmux → just claude.
kk() {
    emulate -L zsh
    local a
    local -a cflags files cprompt
    for a in "$@"; do
        if [[ "$a" == -* ]]; then cflags+=("$a")
        elif [[ -e "$a" ]]; then files+=("${a:a}")
        else cprompt+=("$a"); fi
    done
    if [[ -z "$TMUX" ]]; then
        claude "${cflags[@]}" "${cprompt[@]}"
        return
    fi
    local root paneroot=$PWD
    if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
        paneroot=$root
    fi
    (( ${#files} )) || files=("$paneroot") # no files → open the root as a dir tree
    local nvim_cmd="nvim ${(j: :)${(q@)files}}" # (q@) quotes each file, (j) joins
    # nvim to the left; -d keeps focus here, where claude runs.
    tmux split-window -h -b -d -t "$TMUX_PANE" -l 50% -c "$paneroot" "$(_kk_stay "$nvim_cmd")" || return
    # Name the session after the tmux window, unless --name/-n was passed.
    local -a nameflag=(--name "$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}')")
    local f
    for f in "${cflags[@]}"; do
        [[ "$f" == --name || "$f" == --name=* || "$f" == -n ]] && { nameflag=(); break; }
    done
    (cd "$paneroot" && claude "${nameflag[@]}" "${cflags[@]}" "${cprompt[@]}")
}

# kkactive: a background window per active roblox-notes project running
# `kk /get-notes <project>` from ~/git/roblox; skips existing windows of that name.
kkactive() {
    emulate -L zsh
    local root=~/git/roblox/meta/roblox-notes/active-workstreams d name pane
    [[ -n "$TMUX" ]] || { echo "kkactive: run inside tmux" >&2; return 1; }
    [[ -d "$root" ]] || { echo "kkactive: $root not found" >&2; return 1; }
    local -a have=("${(@f)$(tmux list-windows -F '#{window_name}')}")
    for d in "$root"/*(/N); do
        name=${d:t}
        (( ${have[(Ie)$name]} )) && continue
        pane=$(tmux new-window -d -P -F '#{pane_id}' -n "$name" -c ~/git/roblox) || continue
        tmux send-keys -t "$pane" "kk ${(q):-/get-notes $name}" Enter
    done
}

# tmux
alias trc='nvim ~/.tmux.conf'
alias trs="tmux source ~/.tmux.conf"
alias tl="tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | grep -v '^_'"
alias tka='tmux kill-server'
# tn <name...>: create new tmux session, or attach if it already exists
tn() {
    local name="$*"
    [[ -z "$name" ]] && {
        echo "usage: tn <name>" >&2
        return 1
    }
    if ! tmux has-session -t="$name" 2>/dev/null; then
        tmux new-session -d -s "$name"
    fi
    if [[ -n "$_REAL_TMUX" ]]; then
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    fi
}
# ta [query...]: fuzzy-pick a session to attach to (auto-selects if query matches exactly one)
ta() {
    local session
    session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | grep -v '^_' | fzf -q "$*" --select-1 --exit-0 --reverse | sed 's/ (attached)$//')
    [[ -z "$session" ]] && return
    if [[ -n "$_REAL_TMUX" ]]; then
        tmux switch-client -t "$session"
    else
        tmux attach -t "$session"
    fi
}
# tk [query...]: fuzzy-pick a session to kill (always shows picker, even with exact match)
tk() {
    local session
    session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | grep -v '^_' | fzf -q "$*" --exit-0 --reverse | sed 's/ (attached)$//')
    [[ -z "$session" ]] && return
    tmux kill-session -t "$session"
}
# runall <cmd...>: send <cmd> + Enter to every zsh pane across all tmux sessions
runall() {
    if [[ -z "$*" ]]; then
        echo "usage: runall <command>" >&2
        return 1
    fi
    if ! command -v tmux >/dev/null 2>&1 || ! tmux info >/dev/null 2>&1; then
        echo "runall: no running tmux server" >&2
        return 1
    fi
    local cmd="$*"
    tmux list-panes -a -F '#{pane_current_command} #{pane_id}' |
        awk '$1=="zsh"{print $2}' |
        while read -r pane; do
            [[ "$pane" == "$TMUX_PANE" ]] && continue
            tmux send-keys -t "$pane" "$cmd" Enter
        done
}
# rsa: reload every zsh pane (runall skips the current one) then this pane too
alias rsa='runall rs && rs'
