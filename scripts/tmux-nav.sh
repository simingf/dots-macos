#!/usr/bin/env bash
# tmux-nav.sh <L|D|U|R> <pane> [nvim-server] — prefix m/n/e/i: nvim splits and tmux panes as one layout.
# With a server, nvim moves between its splits first (v:lua.TmuxNav, lua/config/nav.lua; 1 = moved); at
# its edge we select-pane. Entering nvim lands on the entry-edge split (v:lua.TmuxNavEnter).
set -u
dir=$1 pane=$2 srv=${3:-}
case $dir in L) v=h ;; D) v=j ;; U) v=k ;; R) v=l ;; *) exit 2 ;; esac
if [ -n "$srv" ]; then
  [ "$(nvim --server "$srv" --remote-expr "v:lua.TmuxNav('$v')" 2>/dev/null)" = 1 ] && exit 0
  # zoomed: wrap around inside nvim instead (select-pane would unzoom)
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
