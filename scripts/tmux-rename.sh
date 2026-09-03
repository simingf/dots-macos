#!/usr/bin/env bash
# Prompt for a name inside a `display-popup`, then rename the current window/session or create a new
# session (bound to `prefix r` / `prefix R` / `prefix C`). Run in a popup because command-prompt draws on
# the top status line and gets jammed among the window tabs. Escape (or any escape-sequence key) cancels;
# a bare Enter or empty input cancels; otherwise the typed text is used.
# Usage: tmux-rename.sh window|session|new
set -euo pipefail

mode=${1:-}
case "$mode" in
    window|session|new) ;;
    *) echo "tmux-rename: expected 'window', 'session', or 'new', got '$mode'" >&2; exit 2 ;;
esac

printf 'New name: '
IFS= read -rsn1 first || exit 0          # first keystroke (-n1 not -N1: macOS bash 3.2 lacks -N; -s: don't echo yet)
case $first in
    $'\e' | $'\n' | $'\r' | '') exit 0 ;;   # Escape / bare Enter / EOF → cancel
esac
printf '%s' "$first"                      # -s silenced the first char; echo it back
IFS= read -r rest || rest=''              # remainder of the line (normal echo)
name="$first$rest"

case "$mode" in
    window)  tmux rename-window  -- "$name" ;;
    session) tmux rename-session -- "$name" ;;
    new)     tmux new-session -d -A -s "$name"; tmux switch-client -t "$name" ;;   # -A: reuse if it exists, then switch to it
esac
