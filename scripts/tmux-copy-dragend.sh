#!/usr/bin/env bash
# Root-table MouseDragEnd1* handler (.tmux.conf). tmux sends a drag-release to the pane/status/border
# under the cursor, so releasing outside the origin pane drops it and the selection is never copied.
# Copy from whichever pane in the current window still holds a selection.
set -euo pipefail

pane=$(tmux list-panes -F '#{pane_id} #{?selection_present,1,0}' | awk '$2 == "1" { print $1; exit }')
if [ -n "${pane:-}" ]; then
    tmux send-keys -t "$pane" -X copy-pipe-and-cancel
fi
