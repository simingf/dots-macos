#!/usr/bin/env bash
# fzf session switcher in a centered rounded tmux popup.
# Height = session count + 5 (prompt + info + 2 borders + 1 pad), clamped by tmux to fit.
set -euo pipefail

count=$(tmux display-message -p '#{server_sessions}')

tmux display-popup -E -w 70% -h "$((count + 5))" -T ' session ' '
sel=$(tmux list-sessions -F "#{session_attached} #{session_last_attached} #{session_name}|#{session_name}#{?session_attached, (attached),}" \
        | sort -k1,1n -k2,2nr \
        | cut -d" " -f3- \
        | awk -F"|" "{ print \$1 \"|\" NR \": \" \$2 }" \
        | fzf --no-sort --delimiter="[|]" --with-nth=2 --prompt="session> " \
        | cut -d"|" -f1) \
  && [ -n "$sel" ] && tmux switch-client -t "$sel"
' || true
