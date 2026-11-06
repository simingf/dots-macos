#!/bin/sh
# agent-notify.sh <Stop|Notification> — "<tab>: <event>" status-bar notification via
# scripts/tmux-notify.sh. Hook JSON on stdin. Silent no-op outside tmux or with no
# attached client; always exits 0. Stop fires every turn — drop it in settings.json if chatty.
set -u

event="${1:-}"
input=$(cat 2>/dev/null || true)                      # hook JSON on stdin

[ -n "${TMUX_PANE:-}" ] || exit 0

# msg: the hook JSON's "message" (empty without python3).
msg() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$input" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("message",""))
except Exception:
    pass' 2>/dev/null
}

# title = this pane's tmux window name
title=$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null || true)

case "$event" in
  Stop)         body="Turn complete" ;;
  Notification) body="$(msg)"; [ -n "$body" ] || body="needs your attention" ;;
  *) exit 0 ;;
esac

# NOTIFY_TARGET: silent unless a client is attached to this pane's session.
[ -n "$title" ] || title="✳ agent"
notify=$(tmux show-environment -g DOTFILES_DIR 2>/dev/null | cut -d= -f2-)/scripts/tmux-notify.sh
[ -x "$notify" ] && NOTIFY_TARGET="$TMUX_PANE" "$notify" "$title: $body" || true
exit 0
