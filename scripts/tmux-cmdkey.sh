#!/bin/sh
# ⌘-key dispatcher. ghostty sends each ⌘ shortcut as a private sequence (\e[9001~ …), .tmux.conf maps
# them to User keys, and each User bind calls this with the active pane's state so every app gets the
# action it understands — plain bytes end to end, so the same path works in the Linux box's tmux over ssh.
#
# usage: tmux-cmdkey.sh <key> <pane_id> <pane_in_mode> <pane_current_command> <alternate_on> <is_agent> <client>
#   key: a (select all) | c (copy) | x (cut) | z (undo) | Z (redo) | left / right (line start / end) | s (save)
#        clear (⇧⌘⌫: delete the whole input) | bs (⌘⌫: delete the line) | f (find) | p (file picker)
#        slash (toggle comment) | indent / outdent (⌘] / ⌘[)
#
# Order matters: a zsh pane sitting at its prompt is checked before the agent test, because a pane's
# title can stay "✳ …" after Claude exits.
key=$1 pane=$2 in_mode=$3 cmd=$4 alt=$5 agent=$6 client=$7

hex() { printf "$1" | od -An -tx1; }
send_hex() { tmux send-keys -t "$pane" -H $(hex "$1"); }
# ⌘F outside nvim: search the pane's scrollback upward in tmux copy-mode
search() {
    tmux copy-mode -t "$pane"
    tmux command-prompt -t "$client" -T search -p '(search up)' "send-keys -t $pane -X search-backward '%%'"
}

if [ "$in_mode" = 1 ]; then
    # tmux copy-mode: ⌘C / ⌘X copy the selection (same as a drag release), ⌘F searches again
    case $key in c|x) tmux send-keys -t "$pane" -X copy-pipe-and-cancel ;; f) search ;; esac
elif { [ "$cmd" = zsh ] || [ "$cmd" = bash ]; } && [ "$alt" = 0 ]; then
    # shell prompt: forward ghostty's own sequence; widgets in .config/zsh/30-interactive.zsh
    case $key in
        a) send_hex '\033[9001~' ;; c) send_hex '\033[9002~' ;; x) send_hex '\033[9003~' ;;
        z) send_hex '\033[9004~' ;; Z) send_hex '\033[9005~' ;;
        left) send_hex '\033[9006~' ;; right) send_hex '\033[9007~' ;;
        clear) send_hex '\033[9009~' ;; bs) send_hex '\033[9015~' ;; f) search ;;
    esac
elif [ "$cmd" = nvim ] || [ "$cmd" = vim ]; then
    # nvim parses kitty-style keys with the super modifier (9 = 1+super, 10 = 1+super+shift) as
    # <D-…> keys, mapped in .config/nvim/lua/config/keymaps.lua. (tmux's own Home/End don't register.)
    case $key in
        a) send_hex '\033[97;9u' ;; c) send_hex '\033[99;9u' ;; x) send_hex '\033[120;9u' ;;
        z) send_hex '\033[122;9u' ;; Z) send_hex '\033[122;10u' ;; s) send_hex '\033[115;9u' ;;
        left) send_hex '\033[1;9D' ;; right) send_hex '\033[1;9C' ;;
        f) send_hex '\033[102;9u' ;; p) send_hex '\033[112;9u' ;; slash) send_hex '\033[47;9u' ;;
        indent) send_hex '\033[93;9u' ;; outdent) send_hex '\033[91;9u' ;; bs) send_hex '\033[127;9u' ;;
    esac
elif [ "$agent" = 1 ]; then
    # Claude Code: emacs-style input keys. Its input has no selection / select-all / redo, and a drag
    # over its pane is a tmux selection that copies on release, so ⌘A / ⌘C / ⌘X / ⇧⌘Z do nothing here.
    # ⌘F does nothing either: Claude draws on the alternate screen, so copy-mode would only search the
    # visible rows (no scrollback). ⌘⌫ = Ctrl-U (delete to line start).
    # ⇧⌘⌫ = Esc Esc (clears the whole input and saves it to history — ↑ recalls it), but only while idle:
    # mid-turn the first Esc would interrupt Claude. Working = a spinner frame leading the title (same test
    # as tmux-agents.sh, incl. its fallback for locales whose grep can't handle the multibyte range).
    case $key in
        z) tmux send-keys -t "$pane" C-_ ;;
        left) tmux send-keys -t "$pane" C-a ;; right) tmux send-keys -t "$pane" C-e ;;
        bs) tmux send-keys -t "$pane" C-u ;;
        clear)
            printf '⠿◐' | grep -qE '[⠀-⣿◐-◓]' 2>/dev/null || export LC_ALL=en_US.UTF-8
            if tmux display -p -t "$pane" '#{pane_title}' | grep -qE '^[⠀-⣿◐-◓]'; then
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
