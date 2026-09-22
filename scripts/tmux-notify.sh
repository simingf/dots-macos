#!/usr/bin/env bash
# tmux-notify.sh — transient top-right status-bar notification. Does NOT steal focus: tmux popups
# are always modal (they grab the client's keyboard), and tmux has no non-modal floating overlay, so
# notifications live in the status bar instead. Sets the @notify user option (rendered as a highlighted
# segment at the right end of status-right, see .tmux.conf), forces an immediate redraw, then schedules
# a token-guarded clear after $secs. A newer notification replaces the current one and resets the timer
# (its token supersedes the old clear, so the earlier timer won't wipe the newer message early).
#
# Usage:  tmux-notify.sh "<message>"     # keep it short — shares status-right with the clock + agent count
#   env:  NOTIFY_SECS    seconds to show (default 1)
#         NOTIFY_TARGET  a tmux pane/session; if set, only notify when a client is attached to it
#                        (used by .claude/hooks/agent-notify.sh so a detached session stays silent)
set -u

msg="${1:-}"
[ -n "$msg" ] || exit 0
secs="${NOTIFY_SECS:-1}"

# status-right is one line — collapse any newlines/tabs to single spaces.
msg=$(printf '%s' "$msg" | tr '\n\t' '  ')

# Only notify if someone's attached to the target's session (agent-toast case).
if [ -n "${NOTIFY_TARGET:-}" ]; then
  tmux list-clients -t "$NOTIFY_TARGET" -F '#{client_name}' 2>/dev/null | grep -q . || exit 0
fi

# Unique token per notification so a stale timer never clears a newer message.
token="$$-$RANDOM"
tmux set -g @notify "$msg"
tmux set -g @notify_token "$token"
tmux refresh-client -S 2>/dev/null || true   # -S redraws the status line now (don't wait for status-interval)

# Detached, tmux-owned timer: clear only if our token is still the latest.
tmux run-shell -b "sleep $secs; if [ \"\$(tmux show -gqv @notify_token)\" = '$token' ]; then tmux set -g @notify ''; tmux refresh-client -S; fi" 2>/dev/null || true
