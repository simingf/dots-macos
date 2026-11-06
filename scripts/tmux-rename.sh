#!/usr/bin/env bash
# tmux-rename.sh window|session|new — read a name in a popup (prefix r / R / C), then rename or create.
# A popup, since command-prompt gets jammed among the top-status tabs.
#
# Raw byte-at-a-time read so Esc cancels anywhere: a bare Esc cancels, Esc + more bytes (arrows, paste
# markers) is ignored. Bytes come via dd, not `read -n` (it sets its own termios, ignoring MIN/TIME, so a
# bare Esc would hang). Without a tty (tests) stty is skipped and dd reads the pipe.
set -uo pipefail

mode=${1:-}
case "$mode" in
    window|session|new) ;;
    *) echo "tmux-rename: expected 'window', 'session', or 'new', got '$mode'" >&2; exit 2 ;;
esac

_stty=$(stty -g 2>/dev/null || true)
restore()   { [ -n "$_stty" ] && stty "$_stty" 2>/dev/null; return 0; }
trap restore EXIT
[ -n "$_stty" ] && stty -echo -icanon min 1 time 0 2>/dev/null   # raw: block for one byte, no echo
raw_peek()  { [ -n "$_stty" ] && stty min 0 time 1 2>/dev/null; return 0; }   # next read returns after ≤0.1s
raw_block() { [ -n "$_stty" ] && stty min 1 time 0 2>/dev/null; return 0; }   # next read blocks for one byte
getch()     { dd bs=1 count=1 2>/dev/null; }   # one byte, honoring MIN/TIME

printf '\033[38;2;206;172;246mNew name: \033[0m'   # iris label

name=""
while :; do
    key=$(getch)
    case $key in
        ''|$'\n'|$'\r') break ;;                                     # Enter / EOF → done
        $'\e')                                                       # Escape…
            raw_peek; seq=""
            while b=$(getch); [ -n "$b" ]; do                        # …collect any bytes that follow
                seq="$seq$b"; case $b in [A-Za-z~]) break ;; esac     # CSI/SS3 ends on a letter or ~
            done
            raw_block
            [ -z "$seq" ] && { restore; exit 0; }                    # nothing followed → bare Esc → cancel
            ;;                                                        # else arrow/paste marker → ignore
        $'\177'|$'\b') [ -n "$name" ] && { name=${name%?}; printf '\b \b'; } ;;   # Backspace
        $'\025') while [ -n "$name" ]; do name=${name%?}; printf '\b \b'; done ;; # Ctrl-U → clear line
        *) name=$name$key; printf '%s' "$key" ;;                     # printable / pasted char
    esac
done
restore
[ -z "$name" ] && exit 0

case "$mode" in
    window)
        tmux rename-window -- "$name"
        # keep Claude's session name in step: /rename every agent pane in this window
        win=$(tmux display-message -p '#{session_name}:#{window_index}')
        "$(dirname "$0")/tmux-agents.sh" agent-panes "$win" \
            | while IFS= read -r p; do tmux send-keys -t "$p" "/rename $name" Enter; done
        ;;
    session) tmux rename-session -- "$name" ;;
    # Create+switch only after the popup closes (switching from inside breaks -E's auto-close). The server
    # runs it 0.2s later, so the popup pty closing can't kill it like a `nohup … &` child. -A reuses a session.
    new)     tmux run-shell -bC -d 0.2 "new-session -d -A -s \"$name\" ; switch-client -t \"$name\"" ;;
esac
