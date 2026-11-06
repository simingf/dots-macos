#!/usr/bin/env bash
# tmux-fzf-windows.sh [switch|join] — current-session window picker popup (prefix w / @).
#   switch (default): go to the window; join: move the current pane into it.
# Most recent first, current window last. Height = windows + 5.
set -euo pipefail

action="${1:-switch}"

case "$action" in
  switch) prompt="window> "; title=" window " ;;
  join)   prompt="move pane to window> "; title=" send pane to window " ;;
  *) echo "tmux-fzf-windows: unknown action '$action' (expected: switch|join)" >&2; exit 1 ;;
esac

count=$(tmux display-message -p '#{session_windows}')

tmux display-popup -E -e "ACTION=$action" -e "PROMPT=$prompt" -w 70% -h "$((count + 5))" -T "$title" '
sel=$(tmux list-windows -F "#{window_active} #{window_activity} #{session_name}:#{window_index}|#{window_index}: #{window_name}#{?window_active, (current),}" \
        | sort -k1,1n -k2,2nr \
        | cut -d" " -f3- \
        | fzf --no-sort --delimiter="[|]" --with-nth=2 --prompt="$PROMPT" --color=prompt:#ceacf6)
[ -z "$sel" ] && exit 0
target=$(echo "$sel" | cut -d"|" -f1)
case "$ACTION" in
  switch) tmux switch-client -t "$target" ;;
  join)   tmux join-pane -h -d -t "$target" ;;
esac
' || true
