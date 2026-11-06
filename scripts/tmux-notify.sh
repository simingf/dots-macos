#!/usr/bin/env bash
# tmux-notify.sh — transient status-right notification (@notify). Status bar, not a popup: popups are
# always modal. A newer message replaces the current one; a per-message token stops stale clears.
#
# Usage:  tmux-notify.sh "<message>"     # keep it short — shares status-right with the clock + agent count
#   env:  NOTIFY_SECS    seconds to show (default 1)
#         NOTIFY_TARGET  only notify if a client is attached to this pane's session (agent-notify.sh)
set -u

msg="${1:-}"
[ -n "$msg" ] || exit 0
secs="${NOTIFY_SECS:-1}"

# one line only
msg=$(printf '%s' "$msg" | tr '\n\t' '  ')

if [ -n "${NOTIFY_TARGET:-}" ]; then
  tmux list-clients -t "$NOTIFY_TARGET" -F '#{client_name}' 2>/dev/null | grep -q . || exit 0
fi

token="$$-$RANDOM"
tmux set -g @notify "$msg"
tmux set -g @notify_token "$token"
tmux refresh-client -S 2>/dev/null || true   # redraw now, not at status-interval

# Clear later only if our token is still the latest.
tmux run-shell -b "sleep $secs; if [ \"\$(tmux show -gqv @notify_token)\" = '$token' ]; then tmux set -g @notify ''; tmux refresh-client -S; fi" 2>/dev/null || true
