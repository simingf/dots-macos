#!/bin/sh
# agent-status.sh — record this agent pane's status for the tmux agent sidebar (scripts/tmux-agents.sh),
# then nudge the sidebar to repaint. Claude Code runs hooks in the agent's shell, so $TMUX_PANE identifies
# the pane; the state file is keyed by pane id under /tmp and read back by the sidebar to color the dot:
#   Stop         → done → "read" if you're already looking at the pane, else "unread"
#   Notification → "waiting" (permission prompt / question / idle-wait — needs your answer)
#   PostToolUse(Failure) → waiting back to "active" once the answered/approved tool has run
# "working" is detected live from the braille spinner title (not here). Always exits 0.
#
# Separate from agent-notify.sh on purpose: notify = desktop toasts, status = sidebar state.
set -u

[ -n "${TMUX_PANE:-}" ] || exit 0                                   # only meaningful inside tmux
uid=$(id -u 2>/dev/null || echo 0)
f="/tmp/agent-status-${uid}-$(printf '%s' "$TMUX_PANE" | tr -cd '0-9')"
input=$(cat 2>/dev/null || true)                                    # hook JSON on stdin (Notification carries notification_type)

old=$(cat "$f" 2>/dev/null || true)

# turn complete. If the pane is the attached client's visible pane, you're already looking → read; else unread.
_done() {
  vis=$(tmux display-message -p -t "$TMUX_PANE" '#{&&:#{session_attached},#{&&:#{window_active},#{pane_active}}}' 2>/dev/null || echo 0)
  if [ "$vis" = 1 ]; then printf '%s' read > "$f"; else printf '%s' unread > "$f"; fi
}

case "${1:-}" in
  UserPromptSubmit) printf '%s' active > "$f" ;;                     # a new turn began (Stop will end it)
  AskUserQuestion)  printf '%s' waiting > "$f" ;;                    # a multiple-choice prompt is up → needs your answer (foam)
  ToolDone)                                                          # PostToolUse(Failure): you answered the question / approved the
    [ "$old" = waiting ] || exit 0                                  # permission and the tool ran → the turn resumes; else no-op (fires per tool)
    printf '%s' active > "$f" ;;
  PreCompact)       printf '%s' compacting > "$f" ;;                 # context compaction running (busy, but not a normal turn)
  PostCompact)       printf '%s' active > "$f" ;;                     # auto compaction finished (mid-turn); the turn resumes
  PostCompactManual) _done ;;                                        # manual /compact finished — no Stop follows, so it's done
  SessionEnd)       rm -f "$f" ;;                                    # session gone → drop its status file
  StopFailure)      printf '%s' errored > "$f" ;;                    # turn ended on an API error (rate limit/auth/overload) → red
  Stop) _done ;;
  Notification)
    # Notification fires both when Claude pauses mid-turn for your input (permission / needs-input → foam) and
    # as the 60s-idle "your turn" nudge (notification_type=idle_prompt). For any non-idle type, only go foam while
    # the turn is still active (Stop hasn't run since UserPromptSubmit), so an ended conversation stays gray.
    # idle_prompt means Claude is sitting at an empty prompt, so a still-active/waiting turn actually ended without
    # Stop (Esc interrupt, rejected permission) → settle it as done instead of leaving it gold/foam forever.
    case "$input" in
      *'"notification_type":"idle_prompt"'*) case "$old" in active|waiting) _done ;; *) exit 0 ;; esac ;;
      *) case "$old" in active|waiting) printf '%s' waiting > "$f" ;; *) exit 0 ;; esac ;;
    esac ;;
  *) exit 0 ;;
esac

# Transition log for debugging inconsistent dots: "time pane event old -> new" (kept to the last ~500 lines).
log="/tmp/agent-status-log-${uid}"
printf '%s %s %s %s -> %s\n' "$(date '+%m-%d %H:%M:%S')" "$TMUX_PANE" "$1" "${old:--}" "$(cat "$f" 2>/dev/null || echo -)" >> "$log"
[ "$(wc -l < "$log")" -gt 1000 ] && tail -n 500 "$log" > "$log.tmp" && mv "$log.tmp" "$log"

# Repaint the sidebar now rather than waiting for the next tmux event (the title may not change on Stop).
# Resolve the dotfiles dir the same way .tmux.conf does; background it so the hook returns within its timeout.
d="$HOME/dots-$([ "$(uname)" = Linux ] && echo linux || echo macos)"
[ -x "$d/scripts/tmux-agents.sh" ] && "$d/scripts/tmux-agents.sh" refresh >/dev/null 2>&1 &
exit 0
