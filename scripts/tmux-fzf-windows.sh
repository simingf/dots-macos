#!/usr/bin/env bash
# fzf window switcher (current session) in a bottom-anchored, full-width tmux popup.
# Height = window count + 5 (prompt + info + 2 borders + 1 pad), clamped by tmux to fit.
set -euo pipefail

count=$(tmux display-message -p '#{session_windows}')
y=$(tmux display-message -p '#{client_height}')

tmux display-popup -E -x 0 -y "$y" -w 100% -h "$((count + 5))" '
sel=$(tmux list-windows -F "#{window_activity} #{session_name}:#{window_index}|#{window_index}:#{window_name}" \
        | sort -rn \
        | cut -d" " -f2- \
        | fzf --no-sort --delimiter="|" --with-nth=2 --prompt="window> ") \
  && target=$(echo "$sel" | cut -d"|" -f1) \
  && [ -n "$target" ] && tmux switch-client -t "$target"
' || true
