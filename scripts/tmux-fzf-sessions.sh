#!/usr/bin/env bash
# fzf session switcher popup (prefix s). Height = sessions + 5 (prompt, info, borders, pad).
# `_*` sessions are hidden (tmux-lazygit.sh's `_lazygit` stash).
set -euo pipefail

count=$(tmux list-sessions -F '#{session_name}' | grep -vc '^_' || true)

tmux display-popup -E -w 70% -h "$((count + 5))" -T ' session ' '
sel=$(tmux list-sessions -F "#{session_attached} #{session_last_attached} #{session_name}|#{session_name}#{?session_attached, (attached),}" \
        | sort -k1,1n -k2,2nr \
        | cut -d" " -f3- \
        | grep -v "^_" \
        | awk -F"|" "{ print \$1 \"|\" NR \": \" \$2 }" \
        | fzf --no-sort --delimiter="[|]" --with-nth=2 --prompt="session> " --color=prompt:#ceacf6 \
        | cut -d"|" -f1) \
  && [ -n "$sel" ] && tmux switch-client -t "$sel"
' || true
