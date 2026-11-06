#!/bin/sh
# ⌘-key dispatcher: ghostty's \e[90NN~ → tmux UserN → the active app's own action (plain bytes, works over ssh).
#
# usage: tmux-cmdkey.sh <key> <pane_id> <pane_in_mode> <pane_current_command> <alternate_on> <is_agent> <client>
#   key: a (select all) | c (copy) | x (cut) | z (undo) | Z (redo) | left / right (line start / end) | s (save)
#        clear (⇧⌘⌫: delete the whole input) | bs (⌘⌫: delete to line start) | f (find) | p (file picker)
#        slash (toggle comment) | indent / outdent (⌘] / ⌘[) | sleft / sright (⇧⌘←/→: select to line start / end)
#
# Order matters: the zsh-prompt test runs before the agent test (a "✳" title can outlive Claude).
key=$1 pane=$2 in_mode=$3 cmd=$4 alt=$5 agent=$6 client=$7

hex() { printf "$1" | od -An -tx1; }
send_hex() { tmux send-keys -t "$pane" -H $(hex "$1"); }
# ⌘F outside nvim: search the pane's scrollback upward in tmux copy-mode
search() {
    tmux copy-mode -t "$pane"
    tmux command-prompt -t "$client" -T search -p '(search up)' "send-keys -t $pane -X search-backward '%%'"
}

if [ "$in_mode" = 1 ]; then
    # copy-mode: ⌘C/⌘X copy the selection, ⌘F searches again
    case $key in c|x) tmux send-keys -t "$pane" -X copy-pipe-and-cancel ;; f) search ;; esac
elif { [ "$cmd" = zsh ] || [ "$cmd" = bash ]; } && [ "$alt" = 0 ]; then
    # shell prompt: forward the same bytes (widgets in .config/zsh/30-interactive.zsh)
    case $key in
        a) send_hex '\033[9001~' ;; c) send_hex '\033[9002~' ;; x) send_hex '\033[9003~' ;;
        z) send_hex '\033[9004~' ;; Z) send_hex '\033[9005~' ;;
        left) send_hex '\033[9006~' ;; right) send_hex '\033[9007~' ;;
        clear) send_hex '\033[9009~' ;; bs) send_hex '\033[9015~' ;; f) search ;;
        sleft) send_hex '\033[9016~' ;; sright) send_hex '\033[9017~' ;;
    esac
elif [ "$cmd" = nvim ] || [ "$cmd" = vim ]; then
    # kitty-style super keys (9 = super, 10 = super+shift) → <D-…> in lua/config/keymaps.lua
    case $key in
        a) send_hex '\033[97;9u' ;; c) send_hex '\033[99;9u' ;; x) send_hex '\033[120;9u' ;;
        z) send_hex '\033[122;9u' ;; Z) send_hex '\033[122;10u' ;; s) send_hex '\033[115;9u' ;;
        left) send_hex '\033[1;9D' ;; right) send_hex '\033[1;9C' ;;
        f) send_hex '\033[102;9u' ;; p) send_hex '\033[112;9u' ;; slash) send_hex '\033[47;9u' ;;
        indent) send_hex '\033[93;9u' ;; outdent) send_hex '\033[91;9u' ;; bs) send_hex '\033[127;9u' ;;
        clear) send_hex '\033[127;10u' ;;
        sleft) send_hex '\033[1;10D' ;; sright) send_hex '\033[1;10C' ;;
    esac
elif [ "$agent" = 1 ]; then
    # Claude: emacs keys. No ⌘A/C/X/⇧⌘Z (no input selection) or ⌘F (alternate screen, no scrollback).
    # ⇧⌘⌫ = Esc Esc (clears input into history), only when idle: mid-turn Esc interrupts, and while
    # blocked it dismisses the dialog. Working = spinner title or @agent_state (title can sit on ✳).
    case $key in
        z) tmux send-keys -t "$pane" C-_ ;;
        left) tmux send-keys -t "$pane" C-a ;; right) tmux send-keys -t "$pane" C-e ;;
        bs) tmux send-keys -t "$pane" C-u ;;
        clear)
            printf '⠿◐' | grep -qE '[⠀-⣿◐-◓]' 2>/dev/null || export LC_ALL=en_US.UTF-8   # grep needs a UTF-8 locale for the range
            if tmux display -p -t "$pane" '#{pane_title}' | grep -qE '^[⠀-⣿◐-◓]' \
               || case $(tmux show -pqv -t "$pane" @agent_state) in working|blocked) true ;; *) false ;; esac; then
                "$(dirname "$0")/tmux-notify.sh" "Claude is working — Esc would interrupt it"
            else
                tmux send-keys -t "$pane" Escape; sleep 0.1; tmux send-keys -t "$pane" Escape
            fi ;;
    esac
else
    case $key in
        left) tmux send-keys -t "$pane" Home ;; right) tmux send-keys -t "$pane" End ;;
        bs) tmux send-keys -t "$pane" C-u ;; f) [ "$alt" = 0 ] && search ;;
    esac
fi
