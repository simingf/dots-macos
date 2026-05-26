#!/usr/bin/env bash
# fzf session switcher in a bottom-anchored, full-width tmux popup.
# Height = session count + 5 (prompt + info + 2 borders + 1 pad), clamped by tmux to fit.
set -euo pipefail

count=$(tmux display-message -p '#{server_sessions}')
y=$(tmux display-message -p '#{client_height}')

tmux display-popup -E -x 0 -y "$y" -w 100% -h "$((count + 5))" '
sel=$(tmux list-sessions -F "#{session_attached} #{session_last_attached} #{session_name}#{?session_attached, (attached),}" \
        | sort -k1,1n -k2,2nr \
        | cut -d" " -f3- \
        | fzf --no-sort --prompt="session> " \
        | cut -d" " -f1) \
  && [ -n "$sel" ] && tmux switch-client -t "$sel"
' || true
