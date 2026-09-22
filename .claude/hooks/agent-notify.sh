#!/bin/sh
# agent-notify.sh — transient tmux notification when the agent finishes a turn (Stop) or needs
# attention (Notification). The event is passed as $1 from .claude/settings.json (Stop|Notification).
# The agent pipes the hook JSON on stdin.
#
# The tmux window (tab) name — read off $TMUX_PANE the same way the agent sidebar (scripts/tmux-agents.sh)
# does — becomes the notification title, so it reads "<tab>: <event>" (e.g. "myrepo: Turn complete").
# (The finer sidebar status — working/waiting/unread — is NOT reused here: that's a pane-keyed /tmp
# state file for coloring dots, orthogonal to a one-shot notification.)
#
# Delivery: a top-right status-bar notification via scripts/tmux-notify.sh (auto-clears ~3s, no focus
# steal). No OS desktop toast — outside tmux (no $TMUX_PANE) or when the pane's session has no attached
# client, it's a silent no-op. Never fails the hook — always exits 0.
#
# Note: Stop fires on EVERY turn completion, so you'll get a ping per response. Drop the "Stop"
# block in settings.json if that's too chatty and keep only "Notification".
set -u

event="${1:-}"
input=$(cat 2>/dev/null || true)                      # hook JSON on stdin

# tmux-only delivery: no pane → not in tmux → nothing to pop.
[ -n "${TMUX_PANE:-}" ] || exit 0

# msg: pull the "message" string from the hook JSON (used for Notification). Empty if python3 absent.
msg() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$input" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("message",""))
except Exception:
    pass' 2>/dev/null
}

# title = tmux tab (window) name, read off $TMUX_PANE exactly as the sidebar does.
title=$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null || true)

case "$event" in
  Stop)         body="Turn complete" ;;
  Notification) body="$(msg)"; [ -n "$body" ] || body="needs your attention" ;;
  *) exit 0 ;;
esac

# Single-line status-bar notification via tmux-notify.sh: "<tab>: <body>". NOTIFY_TARGET keeps it
# silent when no client is attached to this pane's session.
[ -n "$title" ] || title="✳ agent"
notify=$(tmux show-environment -g DOTFILES_DIR 2>/dev/null | cut -d= -f2-)/scripts/tmux-notify.sh
[ -x "$notify" ] && NOTIFY_TARGET="$TMUX_PANE" "$notify" "$title: $body" || true
exit 0
