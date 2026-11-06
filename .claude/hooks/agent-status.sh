#!/bin/sh
# agent-status.sh <event> — Claude lifecycle hooks → tmux agent dots (scripts/tmux-agents.sh).
# Working/waiting/idle come from the screen (scripts/tmux-agent-state.py); this only stores
# what the screen can't show, in /tmp/agent-status-<uid>-<pane>:
#   StopFailure → errored (an API-error idle looks like any finished turn)
#   PreCompact  → compacting
#   UserPromptSubmit / PostCompact / SessionEnd → cleared
# Every event then nudges a repaint (no wait for the 2s poll). Always exits 0.
set -u

[ -n "${TMUX_PANE:-}" ] || exit 0                                   # only meaningful inside tmux
uid=$(id -u 2>/dev/null || echo 0)
f="/tmp/agent-status-${uid}-$(printf '%s' "$TMUX_PANE" | tr -cd '0-9')"
cat >/dev/null 2>&1 || true                                         # drain the hook JSON on stdin

old=$(cat "$f" 2>/dev/null || true)
case "${1:-}" in
  StopFailure) printf '%s' errored > "$f" ;;
  PreCompact)  printf '%s' compacting > "$f" ;;
  UserPromptSubmit|PostCompact|PostCompactManual|SessionEnd) rm -f "$f" ;;
esac
new=$(cat "$f" 2>/dev/null || true)

# Log flag transitions for debugging (~500 lines kept). Screen state: `tmux-agent-state.py explain <pane>`.
if [ "$old" != "$new" ]; then
  log="/tmp/agent-status-log-${uid}"
  printf '%s %s %s %s -> %s\n' "$(date '+%m-%d %H:%M:%S')" "$TMUX_PANE" "${1:-}" "${old:--}" "${new:--}" >> "$log"
  [ "$(wc -l < "$log")" -gt 1000 ] && tail -n 500 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
fi

# Repaint (dotfiles dir resolved like .tmux.conf); backgrounded to stay within the hook timeout.
d="$HOME/dots-$([ "$(uname)" = Linux ] && echo linux || echo macos)"
[ -x "$d/scripts/tmux-agents.sh" ] && "$d/scripts/tmux-agents.sh" refresh >/dev/null 2>&1 &
exit 0
