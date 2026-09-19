#!/usr/bin/env bash
# Root-table MouseDragEnd1Pane handler (bound in .tmux.conf).
#
# Works around a tmux quirk: a mouse drag-release is attributed to the pane
# under the cursor at release time. If you start a selection in one pane but
# let go over a *different* pane, the release lands in the root key-table (the
# release pane isn't in copy-mode) — and root has no MouseDragEnd1Pane binding,
# so the event is dropped. The origin pane stays in copy-mode with the
# selection sitting there: never copied, never cleared. The default
# copy-pipe-and-cancel only runs when the release happens over the same pane.
#
# Find the pane that actually holds the selection (in the current window) and
# run the normal copy-pipe-and-cancel on it.
set -euo pipefail

pane=$(tmux list-panes -F '#{pane_id} #{?selection_present,1,0}' | awk '$2 == "1" { print $1; exit }')
if [ -n "${pane:-}" ]; then
    tmux send-keys -t "$pane" -X copy-pipe-and-cancel
fi
