#!/bin/sh
# agent-notify.sh — native desktop notification when the agent finishes a turn (Stop) or needs
# attention (Notification). The event is passed as $1 from .claude/settings.json (Stop|Notification),
# mirroring herdr's arg-style hook. The agent pipes the hook JSON on stdin.
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
proj=$(basename "$PWD" 2>/dev/null || echo agent)   # the agent runs hooks with cwd = the project dir
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

case "$event" in
  Stop)         title="✳ agent — $proj"; body="Turn complete" ;;
  Notification) title="✳ agent — $proj"; body="$(msg)"; [ -n "$body" ] || body="needs your attention" ;;
  *) exit 0 ;;
esac

if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$title" -message "$body" -group "agent-$proj" >/dev/null 2>&1 || true
elif [ "$(uname)" = Darwin ]; then
  osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "$title" "$body" >/dev/null 2>&1 || true
fi
exit 0
