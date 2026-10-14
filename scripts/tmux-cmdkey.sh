#!/bin/sh
# ⌘-key dispatcher. ghostty sends each ⌘ shortcut as a private sequence (\e[9001~ …), .tmux.conf maps
# them to User keys, and each User bind calls this with the active pane's state so every app gets the
# action it understands — plain bytes end to end, so the same path works in the Linux box's tmux over ssh.
#
# usage: tmux-cmdkey.sh <key> <pane_id> <pane_in_mode> <pane_current_command> <alternate_on> <is_agent>
#   key: a (select all) | c (copy) | x (cut) | z (undo) | Z (redo) | left / right (line start / end)
#
# Order matters: a zsh pane sitting at its prompt is checked before the agent test, because a pane's
# title can stay "✳ …" after Claude exits.
key=$1 pane=$2 in_mode=$3 cmd=$4 alt=$5 agent=$6

hex() { printf "$1" | od -An -tx1; }
send_hex() { tmux send-keys -t "$pane" -H $(hex "$1"); }

if [ "$in_mode" = 1 ]; then
    # tmux copy-mode: ⌘C / ⌘X copy the selection (same as a drag release)
    case $key in c|x) tmux send-keys -t "$pane" -X copy-pipe-and-cancel ;; esac
elif { [ "$cmd" = zsh ] || [ "$cmd" = bash ]; } && [ "$alt" = 0 ]; then
    # shell prompt: forward ghostty's own sequence; widgets in .config/zsh/30-interactive.zsh
    case $key in
        a) send_hex '\033[9001~' ;; c) send_hex '\033[9002~' ;; x) send_hex '\033[9003~' ;;
        z) send_hex '\033[9004~' ;; Z) send_hex '\033[9005~' ;;
        left) send_hex '\033[9006~' ;; right) send_hex '\033[9007~' ;;
    esac
elif [ "$cmd" = nvim ] || [ "$cmd" = vim ]; then
    # nvim parses kitty-style keys with the super modifier (9 = 1+super, 10 = 1+super+shift) as
    # <D-…> keys, mapped in .config/nvim/lua/config/keymaps.lua. (tmux's own Home/End don't register.)
    case $key in
        a) send_hex '\033[97;9u' ;; c) send_hex '\033[99;9u' ;; x) send_hex '\033[120;9u' ;;
        z) send_hex '\033[122;9u' ;; Z) send_hex '\033[122;10u' ;;
        left) send_hex '\033[1;9D' ;; right) send_hex '\033[1;9C' ;;
    esac
elif [ "$agent" = 1 ]; then
    # Claude Code: emacs-style input keys. Its input has no selection / select-all / redo, and a drag
    # over its pane is a tmux selection that copies on release, so ⌘A / ⌘C / ⌘X / ⇧⌘Z do nothing here.
    case $key in
        z) tmux send-keys -t "$pane" C-_ ;;
        left) tmux send-keys -t "$pane" C-a ;; right) tmux send-keys -t "$pane" C-e ;;
    esac
else
    case $key in left) tmux send-keys -t "$pane" Home ;; right) tmux send-keys -t "$pane" End ;; esac
fi
