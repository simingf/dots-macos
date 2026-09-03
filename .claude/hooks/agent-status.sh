#!/bin/sh
# agent-status.sh — record this agent pane's status for the tmux agent sidebar (scripts/tmux-agents.sh),
# then nudge the sidebar to repaint. Claude Code runs hooks in the agent's shell, so $TMUX_PANE identifies
# the pane; the state file is keyed by pane id under /tmp and read back by the sidebar to color the dot:
#   Stop         → done → "read" if you're already looking at the pane, else "unread"
#   Notification → "waiting" (permission prompt / question / idle-wait — needs your answer)
# "working" is detected live from the braille spinner title (not here). Always exits 0.
#
# Unlike agent-notify.sh this is NOT gated on herdr — the sidebar needs status under herdr too. The two are
# separate on purpose: notify = desktop toasts (herdr-gated), status = sidebar state (always).
set -u

[ -n "${TMUX_PANE:-}" ] || exit 0                                   # only meaningful inside tmux
uid=$(id -u 2>/dev/null || echo 0)
f="/tmp/agent-status-${uid}-$(printf '%s' "$TMUX_PANE" | tr -cd '0-9')"
input=$(cat 2>/dev/null || true)                                    # hook JSON on stdin (Notification carries notification_type)

case "${1:-}" in
  UserPromptSubmit) printf '%s' active > "$f" ;;                     # a new turn began (Stop will end it)
  AskUserQuestion)  printf '%s' waiting > "$f" ;;                    # a multiple-choice prompt is up → needs your answer (red)
  PreCompact)       printf '%s' compacting > "$f" ;;                 # context compaction running (busy, but not a normal turn)
  PostCompact)      printf '%s' active > "$f" ;;                     # compaction finished; the turn resumes
  SessionEnd)       rm -f "$f" ;;                                    # session gone → drop its status file
  StopFailure)      printf '%s' errored > "$f" ;;                    # turn ended on an API error (rate limit/auth/overload) → red
  Stop)
    # turn complete. If the pane is the attached client's visible pane, you're already looking → read; else unread.
    vis=$(tmux display-message -p -t "$TMUX_PANE" '#{&&:#{session_attached},#{&&:#{window_active},#{pane_active}}}' 2>/dev/null || echo 0)
    if [ "$vis" = 1 ]; then printf '%s' read > "$f"; else printf '%s' unread > "$f"; fi ;;
  Notification)
    # Notification fires both when Claude pauses mid-turn for your input (permission / needs-input → red) and
    # as the 60s-idle "your turn" nudge after a turn finished (notification_type=idle_prompt → never red).
    # For any non-idle type, only go red while the turn is still active (Stop hasn't run since UserPromptSubmit),
    # so an ended conversation stays blue/gray.
    case "$input" in
      *'"notification_type":"idle_prompt"'*) : ;;
      *) case "$(cat "$f" 2>/dev/null || true)" in active|waiting) printf '%s' waiting > "$f" ;; *) : ;; esac ;;
    esac ;;
  *) exit 0 ;;
esac

# Repaint the sidebar now rather than waiting for the next tmux event (the title may not change on Stop).
# Resolve the dotfiles dir the same way .tmux.conf does; background it so the hook returns within its timeout.
d="$HOME/dots-$([ "$(uname)" = Linux ] && echo linux || echo macos)"
[ -x "$d/scripts/tmux-agents.sh" ] && "$d/scripts/tmux-agents.sh" refresh >/dev/null 2>&1 &
exit 0
