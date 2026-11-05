#!/usr/bin/env bash
# tmux-nav.sh <L|D|U|R> <pane> [nvim-server] — prefix m/n/e/i (and nvim's <leader>m/n/e/i at its
# edge), so nvim splits and tmux panes move as one layout. In an nvim pane (.tmux.conf passes its
# @nvim_server only when the pane runs nvim) it asks nvim over RPC to move between its splits first
# (v:lua.TmuxNav, lua/config/nav.lua → 1 = moved; a <leader>z zoom counts as all of nvim). Only at
# nvim's edge does it select-pane — while the window is zoomed it wraps around inside nvim instead
# (select-pane would unzoom it). Arriving in an nvim pane, it lands on the split at the entry edge
# (v:lua.TmuxNavEnter: moving right from the pane on the left → nvim's leftmost split, the tree).
# Plain panes keep tmux's own select-pane (wraps around; unzooms).
set -u
dir=$1 pane=$2 srv=${3:-}
case $dir in L) v=h ;; D) v=j ;; U) v=k ;; R) v=l ;; *) exit 2 ;; esac
if [ -n "$srv" ]; then
  [ "$(nvim --server "$srv" --remote-expr "v:lua.TmuxNav('$v')" 2>/dev/null)" = 1 ] && exit 0
  # zoomed: nvim is all that's visible, so wrap around inside it (moving right from its rightmost
  # split → its leftmost) instead of select-pane, which would unzoom
  if [ "$(tmux display -p -t "$pane" '#{window_zoomed_flag}')" = 1 ]; then
    nvim --server "$srv" --remote-expr "v:lua.TmuxNavEnter('$v')" >/dev/null 2>&1
    exit 0
  fi
fi
win=$(tmux display -p -t "$pane" '#{window_id}')
tmux select-pane -t "$pane" -"$dir"
IFS=$'\t' read -r cmd nsrv < <(tmux display -p -t "$win" '#{pane_current_command}	#{@nvim_server}')
[ "$cmd" = nvim ] && [ -n "$nsrv" ] && nvim --server "$nsrv" --remote-expr "v:lua.TmuxNavEnter('$v')" >/dev/null 2>&1
exit 0
