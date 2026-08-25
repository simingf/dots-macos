#!/usr/bin/env bash
# tmux-agents.sh — find, jump to, count, and watch coding-agent panes across all tmux sessions.
#
# Detection (herdr-style, no hook/daemon): an interactive agent sets its terminal title via OSC, which
# tmux captures into #{pane_title} — a braille spinner frame while working ("⠂ <task summary>") and an
# idle marker ("✳ …") when waiting. We match that title. Requires a UTF-8 LC_CTYPE (inherited from the
# tmux client) so grep matches the braille block — every real ghostty/tmux session provides one.
#
# Modes:
#   pick    (default)  fzf popup → switch to the chosen agent pane
#   count              "<working>/<total>" for the status bar (prints nothing when none run)
#   sidebar            toggle a live, clickable agent panel in the current window (bind A)
#   panel              the panel UI itself — runs inside the sidebar pane (double-click/enter jumps)
#   jump <target>      switch to an agent pane by target (used by the picker and panel binds)
set -euo pipefail

# What marks a pane as an agent — matched against the OSC title only. Braille = a working spinner
# frame (generic across agents); "Claude Code"/✳✶✻✽ = an idle agent. Add markers here for other agents.
AGENT_RE='[⠀-⣿]|Claude Code|[✳✶✻✽]'

# _list: one row per agent pane — state <TAB> target <TAB> activity <TAB> window <TAB> title
# state: 0 = working (title starts with a braille spinner frame), 1 = idle/waiting.
# window = tmux window (tab) name; title = the task summary the agent sets. TAB-delimited (titles keep
# spaces). The match tests the TITLE only, so a window merely *named* "node"/"agent" never false-matches.
_list() {
  local target activity window title state
  tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{window_activity}	#{window_name}	#{pane_title}' \
  | while IFS=$'\t' read -r target activity window title; do
      printf '%s' "$title" | grep -qE "$AGENT_RE" || continue          # agent pane? (match the OSC title only)
      if printf '%s' "$title" | grep -qE '^[⠀-⣿]'; then state=0; else state=1; fi   # braille prefix → working
      printf '%s\t%s\t%s\t%s\t%s\n' "$state" "$target" "$activity" "$window" "$title"
    done
}

# _sorted: working agents first, then idle; within a group, most-recently-active first.
_sorted() { _list | sort -t$'\t' -k1,1n -k3,3nr; }

# _fmt: _sorted rows → "target <TAB> ● title  session:window" for fzf (col1 = jump target, hidden by
# --with-nth=2; col2 = the ● working / ○ idle line shown). Shared by the picker and the panel.
_fmt() {
  awk -F'\t' '{ g=($1==0?"●":"○"); split($2,t,":"); printf "%s\t%s  %s  \033[38;5;244m%s:%s\033[0m\n", $2, g, $5, t[1], $4 }'
}

# _jump: switch the client to the agent pane identified by target ($1). Called by the picker + panel.
_jump() {
  [ -n "${1:-}" ] || return 0
  tmux switch-client -t "$1"
  tmux select-window -t "$1"
  tmux select-pane   -t "$1"
}

# _activate: panel click/enter dispatch — a session token (s:) switches sessions, an agent token (a:)
# jumps to that pane, a label ('-') no-ops.
_activate() {
  case "${1:-}" in
    s:?*) tmux switch-client -t "${1#s:}" ;;
    a:?*) _jump "${1#a:}" ;;
    *) : ;;
  esac
}

# __fzf: the picker — runs *inside* pick's popup. Enter jumps (and closes the popup).
__fzf() {
  local rows sel
  rows=$(_sorted) || true
  [ -n "$rows" ] || { tmux display-message "No agents running"; return 0; }
  sel=$(printf '%s\n' "$rows" | _fmt \
        | fzf --ansi --no-sort --delimiter='\t' --with-nth=2 --prompt='agent> ' \
        | cut -f1)
  [ -n "$sel" ] && _jump "$sel"
}

# pick: bottom-anchored full-width popup (matches tmux-fzf-sessions.sh). Height = agents + 5.
_pick() {
  local n y
  n=$(_list | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || { tmux display-message "No agents running"; return 0; }
  y=$(tmux display-message -p '#{client_height}')
  tmux display-popup -E -x 0 -y "$y" -w 100% -h "$((n + 5))" "'$0' __fzf" || true
}

# count: compact "✳ <working>/<total>" for status-right; prints nothing when none run so the bar stays
# clean (the glyph lives here, not in .tmux.conf, so the empty state leaves no orphan mark).
_count() {
  local rows total working
  rows=$(_list) || true
  [ -n "$rows" ] || return 0
  total=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
  working=$(printf '%s\n' "$rows" | grep -c '^0	' || true)
  printf '✳ %s/%s' "$working" "$total"
}

# __lines: NUL-delimited, colored items for the panel — the "spaces" (sessions) list, an "agents"
# divider, then the agent list. Field 1 is a dispatch token (s:<session> / a:<target> / '-' = label);
# field 2 is the shown text. Sessions: attached = ● gold, else ○ muted. Agents: working ● love / idle ○.
__lines() {
  local R=$'\033[0m' LOVE=$'\033[38;2;235;111;146m' MUTE=$'\033[38;2;110;106;134m' TXT=$'\033[1;38;2;224;222;244m' GOLD=$'\033[38;2;246;193;119m'
  local att name state target activity window title dot sess disp
  tmux list-sessions -F '#{session_attached}	#{session_name}' 2>/dev/null | sort -t$'\t' -k2,2 | while IFS=$'\t' read -r att name; do
    [ "${att:-0}" -ge 1 ] && dot="${GOLD}●${R}" || dot="${MUTE}○${R}"
    printf '%s\t%s %s%s%s\0' "s:$name" "$dot" "$TXT" "$name" "$R"
  done
  printf '%s\t%s\0' '-' "${MUTE}agents${R}"                              # section divider (no-op on click)
  _sorted | while IFS=$'\t' read -r state target activity window title; do
    [ "$state" = 0 ] && dot="${LOVE}●${R}" || dot="${MUTE}○${R}"
    sess=${target%%:*}
    disp="${dot} ${TXT}${sess}${R} ${MUTE}· ${window}${R}"$'\n'"  ${MUTE}agent${R}"
    printf '%s\t%s\0' "a:$target" "$disp"
  done
}

# panel: the live, clickable sidebar UI — runs inside the sidebar pane. herdr-style: a "spaces" header
# over the session list, an "agents" divider over the agent list, colored ● / ○ dots, blank-line gaps.
# Double-click or enter switches session (s:) or jumps to the agent pane (a:) WITHOUT closing the panel;
# self-refreshes ~every 2s (start:reload seeds it, load:reload re-runs after a sleep so the chain loops).
_panel() {
  # Fancy visual flags need a recent fzf (--gap/--gap-line, --highlight-line,
  # --no-input; ~0.52+). Debian ships 0.44, which aborts on an unknown flag —
  # killing the pane. Probe --help and add only what's supported so the sidebar
  # still renders (just plainer) on old fzf.
  local extra=() help; help=$(fzf --help 2>&1)
  case "$help" in *--no-input*)       extra+=(--no-input) ;; esac
  case "$help" in *--gap-line*)       extra+=(--gap=1 --gap-line=' ') ;; esac
  case "$help" in *--highlight-line*) extra+=(--highlight-line) ;; esac
  fzf --read0 --ansi --layout=reverse --info=hidden \
      ${extra[@]+"${extra[@]}"} --pointer='' --marker='' \
      --header='spaces ' --header-first --delimiter='\t' --with-nth=2 \
      --color='bg+:#26233a,fg+:-1,gutter:-1,header:#6e6a86,pointer:-1' \
      --bind "start:reload('$0' __lines)" \
      --bind "load:reload(sleep 2; '$0' __lines)" \
      --bind "double-click:execute-silent('$0' activate {1})" \
      --bind "enter:execute-silent('$0' activate {1})" \
      >/dev/null 2>&1 || true
}

# _sidebar_open: create the panel as a 40-col LEFT split in the current window (tagged @agent_sidebar,
# focus stays put via -d). No-op if this window already has one — so `prefix c` can call it blindly.
_sidebar_open() {
  tmux list-panes -F '#{@agent_sidebar}' | grep -q '^1$' && return 0
  local pane
  pane=$(tmux split-window -h -b -l 40 -d -P -F '#{pane_id}' "'$0' panel") || return 0
  # If the panel command dies immediately (e.g. fzf too old), the pane is already
  # gone — tag it defensively so a stale pane never surfaces "no such pane".
  [ -n "$pane" ] && tmux set-option -p -t "$pane" @agent_sidebar 1 2>/dev/null
  return 0
}

# sidebar: TOGGLE the panel — open it (left, via _sidebar_open) or, if this window already has one,
# close it. Self-heals if you closed it manually (`x`/esc). Per-window: a split can only live in one
# window, so each window tracks its own.
_sidebar() {
  local existing
  existing=$(tmux list-panes -F '#{pane_id} #{@agent_sidebar}' | awk '$2 == "1" { print $1; exit }')
  if [ -n "$existing" ]; then tmux kill-pane -t "$existing"; else _sidebar_open; fi
}

# reap: close window $1 when its only remaining pane(s) are the sidebar — so exiting your last real
# pane closes the tab instead of leaving a lone sidebar. Wired to window-layout-changed in .tmux.conf.
_reap() {
  local win="${1:-}" total nonsb
  [ -n "$win" ] || return 0
  total=$(tmux list-panes -t "$win" -F x 2>/dev/null | wc -l | tr -d ' ')
  [ "${total:-0}" -ge 1 ] || return 0                                   # window already gone
  nonsb=$(tmux list-panes -t "$win" -F '#{@agent_sidebar}' 2>/dev/null | grep -vc '^1$' || true)
  if [ "${nonsb:-1}" = 0 ]; then tmux kill-window -t "$win" 2>/dev/null || true; fi
}

case "${1:-pick}" in
  pick)    _pick ;;
  __fzf)   __fzf ;;      # internal: invoked inside the popup
  count)   _count ;;
  sidebar)      _sidebar ;;
  sidebar-open) _sidebar_open ;;  # internal: invoked by `prefix c` to seed the left panel
  panel)        _panel ;;         # internal: invoked inside the sidebar pane
  __lines)      __lines ;;            # internal: invoked by the panel's reload binds
  activate)     _activate "${2:-}" ;; # internal: invoked by the panel click/enter binds
  reap)         _reap "${2:-}" ;;     # internal: invoked by the window-layout-changed hook
  *) echo "tmux-agents: unknown mode '${1}' (expected: pick|count|sidebar)" >&2; exit 1 ;;
esac
