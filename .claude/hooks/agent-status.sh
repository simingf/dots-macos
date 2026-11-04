#!/bin/sh
# agent-status.sh — Claude Code lifecycle hooks → tmux agent dots (scripts/tmux-agents.sh).
#
# Working / waiting / idle are read off the screen by scripts/tmux-agent-state.py, not here. This hook only
# records what the screen can't show, as a flag in /tmp/agent-status-<uid>-<pane> (Claude runs hooks in the
# agent's shell, so $TMUX_PANE is the pane), and the detector consumes it:
#   StopFailure → errored    the turn died on an API error (the idle screen looks like any finished turn)
#   PreCompact  → compacting  shown iris while the screen says working
#   UserPromptSubmit / PostCompact / SessionEnd → flag cleared
# Every event — including the flag-less Stop / Notification / AskUserQuestion / ToolDone — then nudges a
# repaint, so transitions land at once instead of on the next 2s poll. Always exits 0.
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

# Flag transitions, for debugging a wrong dot: "time pane event old -> new" (kept to the last ~500 lines).
# Screen-state transitions aren't logged — `scripts/tmux-agent-state.py explain <pane>` shows those live.
if [ "$old" != "$new" ]; then
  log="/tmp/agent-status-log-${uid}"
  printf '%s %s %s %s -> %s\n' "$(date '+%m-%d %H:%M:%S')" "$TMUX_PANE" "${1:-}" "${old:--}" "${new:--}" >> "$log"
  [ "$(wc -l < "$log")" -gt 1000 ] && tail -n 500 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
fi

# Repaint now. Resolve the dotfiles dir the same way .tmux.conf does; background it so the hook returns
# within its timeout.
d="$HOME/dots-$([ "$(uname)" = Linux ] && echo linux || echo macos)"
[ -x "$d/scripts/tmux-agents.sh" ] && "$d/scripts/tmux-agents.sh" refresh >/dev/null 2>&1 &
exit 0
