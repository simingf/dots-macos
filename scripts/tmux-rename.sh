#!/usr/bin/env bash
# Prompt for a name inside a `display-popup`, then rename the current window/session or create a
# new session (bound to `prefix r` / `prefix R` / `prefix C`). Run in a popup because command-prompt
# draws on the top status line and gets jammed among the window tabs.
#
# The name is read one byte at a time in raw mode so Escape cancels at ANY point: a bare Esc is our
# cancel, while Esc followed by more bytes is an arrow/bracketed-paste sequence we consume and ignore.
# Backspace and Ctrl-U (clear line) work; pasted text arrives as plain chars and is appended. The
# bare-Esc-vs-sequence timing uses stty MIN/TIME, and bytes are read with `dd` — NOT bash `read -n`,
# which sets its own termios and ignores MIN/TIME (so a bare Esc would block forever). stty is a no-op
# and dd reads from the pipe when stdin isn't a tty (tests).
# Usage: tmux-rename.sh window|session|new
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
getch()     { dd bs=1 count=1 2>/dev/null; }   # one byte, honoring the tty MIN/TIME (bash `read -n` sets its own termios and ignores them → bare Esc hangs)

printf '\033[38;2;206;172;246mNew name: \033[0m'   # iris label; reset so typed text is default (white)

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
        $'\025') while [ -n "$name" ]; do name=${name%?}; printf '\b \b'; done ;; # Ctrl-U → clear line (Cmd-Delete via ghostty keybind → \x15)
        *) name=$name$key; printf '%s' "$key" ;;                     # printable / pasted char
    esac
done
restore
[ -z "$name" ] && exit 0

case "$mode" in
    window)  tmux rename-window  -- "$name" ;;
    session) tmux rename-session -- "$name" ;;
    new)     tmux new-session -d -A -s "$name"; tmux switch-client -t "$name" ;;   # -A: reuse if it exists, then switch to it
esac
