#!/bin/sh
# agent-notify.sh — native desktop notification when the agent finishes a turn (Stop) or needs
# attention (Notification). The event is passed as $1 from .claude/settings.json (Stop|Notification),
# mirroring herdr's arg-style hook. The agent pipes the hook JSON on stdin.
#
# Title + subtitle come from tmux, via the SAME introspection the agent sidebar (scripts/tmux-agents.sh)
# reads off a pane: the tmux window (tab) name is the title, and #{pane_title} — the one-line summary
# Claude sets as its OSC title — is the subtitle, with its leading spinner/marker glyph ("⠂ …"/"✳ …")
# stripped. So a toast reads "<tab>" over "<what that agent is doing>". Outside tmux (no $TMUX_PANE) the
# title falls back to the project dir. (The finer sidebar status — working/waiting/unread — is NOT reused
# here: that's a pane-keyed /tmp state file for coloring dots, orthogonal to a one-shot toast.)
#
# This is the plain-tmux/terminal replica of herdr's system toast. Under herdr (HERDR_ENV=1) herdr
# already toasts on agent state change, so this no-ops to avoid double notifications.
# Portable: terminal-notifier (or osascript) on macOS, notify-send on Linux; silent no-op if none
# exist (e.g. a headless dev box). Never fails the hook — always exits 0.
#
# Note: Stop fires on EVERY turn completion, so outside herdr you'll get a ping per response. Drop
# the "Stop" block in settings.json if that's too chatty and keep only "Notification".
set -u

[ "${HERDR_ENV:-}" = "1" ] && exit 0

event="${1:-}"
proj=$(basename "$PWD" 2>/dev/null || echo agent)     # the agent runs hooks with cwd = the project dir
input=$(cat 2>/dev/null || true)                      # hook JSON on stdin

# msg: pull the "message" string from the hook JSON (used for Notification). Empty if python3 absent.
msg() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$input" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("message",""))
except Exception:
    pass' 2>/dev/null
}

# title = tmux tab (window) name; subtitle = the pane's OSC title (Claude's autogen one-line summary),
# both read off $TMUX_PANE exactly as the sidebar does. The pane title is "<glyph> <summary>" when a
# marker is present (a braille frame while working, ✳/✶/✻/✽ when idle), so if the first char isn't
# alphanumeric we drop through the first space to leave just the summary.
title=""; subtitle=""
if [ -n "${TMUX_PANE:-}" ]; then
  title=$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null || true)
  pane_title=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_title}' 2>/dev/null || true)
  case "$pane_title" in
    ""|[A-Za-z0-9]*) subtitle="$pane_title" ;;        # already summary text (or empty)
    *)               subtitle="${pane_title#* }" ;;   # drop leading marker glyph + its space
  esac
fi
[ -n "$title" ] || title="✳ agent — $proj"            # not in tmux → project-dir title, no subtitle

case "$event" in
  Stop)         body="Turn complete" ;;
  Notification) body="$(msg)"; [ -n "$body" ] || body="needs your attention" ;;
  *) exit 0 ;;
esac

if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$title" -subtitle "$subtitle" -message "$body" -group "agent-$proj" >/dev/null 2>&1 || true
elif [ "$(uname)" = Darwin ]; then
  osascript -e "display notification \"$body\" with title \"$title\" subtitle \"$subtitle\"" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  b="$body"; [ -n "$subtitle" ] && b="$subtitle
$b"                                                   # notify-send has no subtitle — fold it into the body
  notify-send "$title" "$b" >/dev/null 2>&1 || true
fi
exit 0
