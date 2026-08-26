# tmux session module — sourced by .zshrc when inside a real tmux ($TMUX set and
# HERDR_ENV != 1). Defines the tmux `kk` layout (mirrors the herdr one) plus the
# tmux session helpers. Relies on _kk_recent_nested_repo() / claude() / _REAL_TMUX
# from .zshrc (defined before the source tail). Byte-identical across mac & linux —
# no host-specific paths (claude/nvim/lazygit resolve per-platform from .zshrc).

# kk: tmux split matching the herdr kk — claude (LEFT), nvim (MIDDLE, full height),
# and in a git repo (or a folder with a repo nested ≤2 deep) lazygit (RIGHT-top) +
# terminal (RIGHT-bottom); otherwise claude/nvim 50/50 with terminal under nvim.
# Args starting with - go to claude; others are files opened in nvim (default: the
# root as a dir tree). Panes run their tool as the command so they close on exit;
# -d keeps focus on the origin pane, where claude runs last. Outside tmux → claude.
kk() {
    emulate -L zsh
    local a
    local -a cflags files
    for a in "$@"; do [[ "$a" == -* ]] && cflags+=("$a") || files+=("${a:a}"); done
    if [[ -z "$TMUX" ]]; then
        claude "${cflags[@]}"
        return
    fi
    local root paneroot=$PWD lgroot
    if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
        paneroot=$root lgroot=$root
    else
        lgroot=$(_kk_recent_nested_repo)
    fi
    (( ${#files} )) || files=("$paneroot") # no files → open the root as a dir tree
    local nvim_cmd="nvim ${(j: :)${(q@)files}}" # (q@) quotes each file, (j) joins
    local right lg
    if [[ -n "$lgroot" ]]; then
        # claude keeps 35% (left); right region 65% → nvim 54% / lazygit 46% (≈35/30
        # of total); lazygit split down 30% for the terminal. nvim stays full-height.
        right=$(tmux split-window -h -d -l 65% -c "$paneroot" -P -F '#{pane_id}' "$nvim_cmd") || return
        lg=$(tmux split-window -h -d -t "$right" -l 46% -c "$lgroot" -P -F '#{pane_id}' "lazygit") || return
        tmux split-window -v -d -t "$lg" -l 30% -c "$paneroot" || return
    else
        # claude/nvim 50/50; terminal under nvim (right-bottom 30%).
        right=$(tmux split-window -h -d -l 50% -c "$paneroot" -P -F '#{pane_id}' "$nvim_cmd") || return
        tmux split-window -v -d -t "$right" -l 30% -c "$paneroot" || return
    fi
    (cd "$paneroot" && claude "${cflags[@]}") # claude in the origin (left) pane
}

# tmux
alias trc='nvim ~/.tmux.conf'
alias trs="tmux source ~/.tmux.conf"
alias tl="tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}'"
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
    session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | fzf -q "$*" --select-1 --exit-0 --reverse | sed 's/ (attached)$//')
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
    session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | fzf -q "$*" --exit-0 --reverse | sed 's/ (attached)$//')
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
