#!/usr/bin/env bash
# tmux-nav.sh <L|D|U|R> <pane> <nvim-server> <zoomed> — prefix m/n/e/i in an nvim pane (bound in
# .tmux.conf only when the pane runs nvim and published @nvim_server): move between nvim's splits
# first, and only at nvim's edge on to the next tmux pane, so splits and panes share one set of keys.
# Asks nvim over RPC (v:lua.TmuxNav in lua/config/tmux_lazygit.lua → 1 = moved inside nvim). An
# unreachable nvim falls through to a plain select-pane; a zoomed pane stays put at the edge
# (select-pane would unzoom it).
set -u
dir=$1 pane=$2 srv=$3 zoomed=$4
case $dir in L) v=h ;; D) v=j ;; U) v=k ;; R) v=l ;; *) exit 2 ;; esac
[ "$(nvim --server "$srv" --remote-expr "v:lua.TmuxNav('$v')" 2>/dev/null)" = 1 ] && exit 0
[ "$zoomed" = 1 ] && exit 0
tmux select-pane -t "$pane" -"$dir"
