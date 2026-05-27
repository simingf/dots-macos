#!/usr/bin/env bash
# Spatial focus across monitors with wrap-around.
#
# Workaround for https://github.com/nikitabobko/AeroSpace/issues/1491:
# aerospace's `focus --boundaries all-monitors-outer-frame` lands on the MRU
# window of the destination monitor instead of the spatially-nearest one.
#
# In-workspace case: 1 IPC call (~30ms).
# Cross-monitor case: in-workspace probe + 2 list queries run concurrently,
# then 1 swift binary + 1 final focus. The probe's failure cost is hidden
# behind the list queries it would otherwise block.
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

# Probe and heavy queries run in parallel. The probe attempts the in-workspace
# focus; on success we exit and the (wasted) query results are discarded. On
# failure aerospace did not move focus, so the concurrent list snapshots are
# still consistent with the pre-focus state.
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

aerospace focus --window-id "$target"
