#!/usr/bin/env bash
# tmux-agents.sh — Claude agent picker, status-bar count, and per-tab dots (tmux UI glue).
# Detection lives in tmux-agent-state.py; its rows: status <TAB> sess:win.pane <TAB> window <TAB> pane_id <TAB> title.
# Dots: gold working, foam waiting, love errored, iris compacting, gray ● unread, gray ○ read.
# Re-read on tmux hooks, Claude hooks (agent-status.sh), and the status-right `count` poll.
#
# Modes:
#   pick    (default)  fzf popup → switch to the chosen agent pane
#   count              "✳ <busy>/<total>" for status-right (nothing when none run); also repaints the dots
#   agent-panes <win>  pane ids of the agent panes in a window (tmux-rename.sh)
#   refresh | refresh-agents | mark-read   internal, from tmux hooks
#
# No set -e / pipefail: hooks run during churn when targets can vanish, and a non-zero exit shows as a
# pane-blanking "returned 1" overlay. Failures are guarded inline instead.
set -u

STATE="$(dirname "$0")/tmux-agent-state.py"

# Vendored fzf first: Debian's is old, and the server PATH may miss ~/.local/bin.
FZF="$HOME/.local/bin/fzf"; [ -x "$FZF" ] || FZF=fzf

# Detector rows (busy first, then most recent). Also advances per-pane state, so every call is a re-read.
_agents_status() { python3 "$STATE" status 2>/dev/null || true; }

# rows → "target <TAB> ● session:window  title" for the picker (col1 hidden by --with-nth=2).
_fmt() {
  awk -F'\t' '
    function col(st) {
      if (st=="working")    return "\033[38;2;246;193;119m"   # gold
      if (st=="waiting")    return "\033[38;2;156;207;216m"   # foam
      if (st=="errored")    return "\033[38;2;235;111;146m"   # love
      if (st=="compacting") return "\033[38;2;196;167;231m"   # iris
      return "\033[38;2;110;106;134m"                          # unread/read → gray
    }
    { c=index($2,":"); s=substr($2,1,c-1); g=($1=="read"?"○":"●")
      printf "%s\t%s%s\033[0m \033[1;38;2;224;222;244m%s:%s\033[0m  \033[38;2;110;106;134m%s\033[0m\n", $2, col($1), g, s, $3, $5 }'
}

# Attached client's active pane (not a @sidebar), or empty.
_focused_pane() {
  tmux list-panes -a -F '#{session_attached}	#{window_active}	#{pane_active}	#{@sidebar}	#{pane_id}' 2>/dev/null \
  | awk -F'\t' '$1>=1 && $2==1 && $3==1 && $4!=1 {print $5; exit}' || true
}

_jump() {
  [ -n "${1:-}" ] || return 0
  tmux switch-client -t "$1"
  tmux select-window -t "$1"
  tmux select-pane   -t "$1"
}

# Runs inside pick's popup.
__fzf() {
  local rows sel
  rows=$(_agents_status)
  [ -n "$rows" ] || { "$(dirname "$0")/tmux-notify.sh" "No agents running"; return 0; }
  sel=$(printf '%s\n' "$rows" | _fmt \
        | "$FZF" --ansi --no-sort --delimiter='\t' --with-nth=2 --prompt='agent> ' \
        | cut -f1)
  [ -n "$sel" ] && _jump "$sel"
}

# Popup height = agents + 5.
_pick() {
  local n
  n=$(python3 "$STATE" panes 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || { "$(dirname "$0")/tmux-notify.sh" "No agents running"; return 0; }
  tmux display-popup -E -w 70% -h "$((n + 5))" -T ' agents ' "'$0' __fzf" || true
}

# "✳ busy/total" (busy = working|compacting), empty when none run. Paints in the background — #() must exit fast.
_count() {
  local rows total busy
  rows=$(_agents_status)
  ( _paint "$rows" >/dev/null 2>&1 & )
  [ -n "$rows" ] || return 0
  total=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
  busy=$(printf '%s\n' "$rows" | grep -cE '^(working|compacting)	' || true)
  printf '✳ %s/%s' "$busy" "$total"
}

# Status → tmux #[…] styled glyph (not ANSI), drawn via #{E:@agent_dot}.
_dot() {
  case "${1:-}" in
    working)    printf ' #[fg=#f6c177]●#[default]' ;;
    waiting)    printf ' #[fg=#9ccfd8]●#[default]' ;;
    errored)    printf ' #[fg=#eb6f92]●#[default]' ;;
    compacting) printf ' #[fg=#c4a7e7]●#[default]' ;;
    unread)     printf ' #[fg=#6e6a86]●#[default]' ;;
    read)       printf ' #[fg=#6e6a86]○#[default]' ;;
    *)          : ;;
  esac
}

# paint [rows]: each window's @agent_dot = its most urgent agent (errored > waiting > compacting > working >
# unread > read). Diffed against live tmux state, so steady state redraws nothing and runs always converge.
_paint() {
  local map changed w cur want
  map=$(printf '%s\n' "${1:-$(_agents_status)}" | awk -F'\t' '
    BEGIN { rank["read"]=0; rank["unread"]=1; rank["working"]=2; rank["compacting"]=3; rank["waiting"]=4; rank["errored"]=5 }
    NF { tab=$2; sub(/\.[0-9]+$/, "", tab)                          # target sess:win.pane → window key sess:win
         if (!(tab in best) || rank[$1] >= r[tab]) { best[tab]=$1; r[tab]=rank[$1] } }
    END { for (t in best) print t"\t"best[t] }') || true
  changed=0
  while IFS=$'\t' read -r w cur; do
    [ -n "$w" ] || continue
    want=$(_dot "$(printf '%s\n' "$map" | awk -F'\t' -v w="$w" '$1==w {print $2; exit}')")
    [ "$want" = "$cur" ] && continue
    if [ -n "$want" ]; then tmux set-option -w -t "$w" @agent_dot "$want" 2>/dev/null || true
    else tmux set-option -wu -t "$w" @agent_dot 2>/dev/null || true; fi
    changed=1
  done < <(tmux list-windows -a -F '#{session_name}:#{window_index}	#{@agent_dot}' 2>/dev/null)
  [ "$changed" = 1 ] && tmux refresh-client -S 2>/dev/null || true
}

# Delete hook flag files of dead panes (kill/crash skips SessionEnd; a reused pane id would inherit them).
_prune() {
  local live f d
  live=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr -d '%')
  for f in "/tmp/agent-status-${UID:-0}"-*; do
    [ -e "$f" ] || continue                                              # no matches → literal glob, skip
    d=${f##*-}
    printf '%s\n' "$live" | grep -qx "$d" || rm -f "$f"
  done
}

_refresh() {
  _paint
  _prune
}

# pane-title-changed: the spinner fires many times/sec; the mkdir lock coalesces a burst into one refresh.
_refresh_agents() {
  local lock="/tmp/agent-refresh-${UID:-0}.lock"
  mkdir "$lock" 2>/dev/null || return 0                                 # already scheduled
  ( trap 'rmdir "$lock" 2>/dev/null' EXIT; sleep 0.4; _refresh ) &
}

# Focus changed: the pane you landed on is now seen (clear @agent_unread: ● → ○).
_mark_read() {
  local pid
  pid=$(_focused_pane)
  [ -n "$pid" ] && tmux set-option -pu -t "$pid" @agent_unread 2>/dev/null
  _refresh
}

case "${1:-pick}" in
  pick)           _pick ;;
  __fzf)          __fzf ;;                                   # internal
  count)          _count ;;
  agent-panes)    [ -n "${2:-}" ] && python3 "$STATE" panes "$2" 2>/dev/null ;;
  refresh)        _refresh ;;
  refresh-agents) _refresh_agents ;;
  mark-read)      _mark_read ;;
  *) echo "tmux-agents: unknown mode '${1}' (expected: pick|count|agent-panes|refresh|refresh-agents|mark-read)" >&2; exit 1 ;;
esac
