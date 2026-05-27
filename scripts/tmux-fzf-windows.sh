#!/usr/bin/env bash
# fzf window picker (current session) in a bottom-anchored, full-width tmux popup.
# Action: 'switch' (default) jumps to the picked window; 'join' moves the current pane into the picked window.
# Current window sorts to the bottom with a (current) marker; others ordered by recent activity.
# Height = window count + 5 (prompt + info + 2 borders + 1 pad), clamped by tmux to fit.
set -euo pipefail

action="${1:-switch}"

case "$action" in
  switch) prompt="window> " ;;
  join)   prompt="move pane to window> " ;;
  *) echo "tmux-fzf-windows: unknown action '$action' (expected: switch|join)" >&2; exit 1 ;;
esac

count=$(tmux display-message -p '#{session_windows}')
y=$(tmux display-message -p '#{client_height}')

tmux display-popup -E -e "ACTION=$action" -e "PROMPT=$prompt" -x 0 -y "$y" -w 100% -h "$((count + 5))" '
sel=$(tmux list-windows -F "#{window_active} #{window_activity} #{session_name}:#{window_index}|#{window_index}: #{window_name}#{?window_active, (current),}" \
        | sort -k1,1n -k2,2nr \
        | cut -d" " -f3- \
        | fzf --no-sort --delimiter="[|]" --with-nth=2 --prompt="$PROMPT")
[ -z "$sel" ] && exit 0
target=$(echo "$sel" | cut -d"|" -f1)
case "$ACTION" in
  switch) tmux switch-client -t "$target" ;;
  join)   tmux join-pane -h -d -t "$target" ;;
esac
' || true
