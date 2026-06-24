#!/usr/bin/env bash
# Spatial focus across monitors with wrap-around.
#
# Workaround for https://github.com/nikitabobko/AeroSpace/issues/1491:
# aerospace's `focus --boundaries all-monitors-outer-frame` lands on the MRU
# window of the destination monitor instead of the spatially-nearest one.
#
# Left/right: probe in-workspace first (fast path), fall back to cross-monitor.
# Up/down: pure spatial within the workspace — aerospace's built-in focus
# incorrectly moves between horizontally-tiled windows on up/down, so we
# bypass it and use CoreGraphics frames directly.
#
# Usage: aerospace-focus.sh left|right|up|down

set -eu

dir="${1:?usage: $0 left|right|up|down}"

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
src="$script_dir/find-edge-window.swift"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/aerospace-focus"
bin="$cache_dir/find-edge-window"
if [ ! -x "$bin" ] || [ "$src" -nt "$bin" ]; then
  mkdir -p "$cache_dir"
  swiftc -O "$src" -o "$bin"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/aerofocus.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

if [ "$dir" = "up" ] || [ "$dir" = "down" ]; then
  # Pure spatial: find a window actually above/below on this workspace.
  # The binary returns a window-id, "cycle" (stacked/accordion), or nothing.
  focused_id=$(aerospace list-windows --focused --format '%{window-id}')
  aerospace list-windows --workspace focused --format '%{window-id}' > "$tmp/ws"
  target=$("$bin" "--spatial" "$dir" "$focused_id" "$tmp/ws")
  if [ "$target" = "cycle" ]; then
    aerospace focus "$dir"
  elif [ -n "$target" ]; then
    aerospace focus --window-id "$target"
  fi
  exit 0
fi

# Left/right: probe in-workspace first, fall back to cross-monitor.
aerospace focus --boundaries workspace --boundaries-action fail "$dir" 2>/dev/null \
  && echo ok > "$tmp/probe" &
probe_pid=$!
aerospace list-monitors --format '%{monitor-id}' > "$tmp/m" &
aerospace list-windows --all --format '%{window-id}%{tab}%{monitor-id}%{tab}%{workspace}%{tab}%{workspace-is-visible}%{tab}%{workspace-is-focused}' > "$tmp/w" &

wait "$probe_pid" 2>/dev/null || true
[ -f "$tmp/probe" ] && exit 0

wait
target=$("$bin" "$dir" "$tmp/m" "$tmp/w")
[ -z "$target" ] && exit 0

case "$target" in
  ws:*) aerospace workspace "${target#ws:}" ;;
  *)    aerospace focus --window-id "$target" ;;
esac
