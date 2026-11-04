#!/usr/bin/env bash
# tmux-agents.sh — find, jump to, count, and surface Claude Code agent status across all tmux sessions.
#
# This file is the tmux UI glue. WHICH panes are agents and WHAT state they're in comes from
# scripts/tmux-agent-state.py (a port of herdr's screen + title detection — see its docstring), which emits
# one row per agent pane: status <TAB> sess:win.pane <TAB> window <TAB> pane_id <TAB> title.
# Statuses → dots: gold ●=working, foam ●=waiting (needs your answer), love ●=errored, iris ●=compacting,
# gray ●=done-unread, gray ○=read. A window shows its most urgent agent's dot (window-status-format
# draws @agent_dot); a window with no agent gets none. (The retired clickable agent sidebar lives in
# archive/agent-sidebar/.)
#
# When we re-read: structural hooks + focus changes (immediate), pane-title-changed (debounced), every Claude
# hook (.claude/hooks/agent-status.sh), and `count` in status-right — re-run every status-interval, it's the
# poll that catches screen-only transitions (no title change, no hook).
#
# Modes:
#   pick    (default)  fzf popup → switch to the chosen agent pane
#   count              "✳ <busy>/<total>" for status-right (nothing when none run); also repaints the dots
#   paint              write each window's @agent_dot
#   agent-panes <win>  pane ids of the agent panes in a window (tmux-rename.sh)
#   refresh | refresh-agents | mark-read   internal, from tmux hooks
#
# No `set -e`/`pipefail`: every function here is fire-and-forget tmux glue run from `run-shell -b` hooks
# *during* structural churn, when a `tmux list-*` target can be transiently gone. pipefail would turn that
# into a failed pipeline and set -e would abort before the code's own `|| return 0` / `${x:-0}` guards run —
# surfacing as a pane-blanking "'…tmux-agents.sh …' returned 1" overlay. Keep nounset (the code guards for it).
set -u

STATE="$(dirname "$0")/tmux-agent-state.py"

# Prefer a vendored fzf over an old system one: Debian's apt fzf (0.44) is too old
# for the panel's flags, and tmux resolves bare `fzf` from the server PATH, which on
# non-login setups misses ~/.local/bin. Pick the vendored one explicitly when present.
FZF="$HOME/.local/bin/fzf"; [ -x "$FZF" ] || FZF=fzf

# _agents_status: the detector's rows (busy first, then most-recently-active). Also advances its per-pane
# state, so every caller doubles as a re-read.
_agents_status() { python3 "$STATE" status 2>/dev/null || true; }

# _fmt: _agents_status rows → "target <TAB> ● session:window  description" for the picker (col1 = jump target,
# hidden by --with-nth=2; col2 = the shown line). Dot colored like the tab dots (_dot), session:window in
# bright rose, the agent's task summary (its title) trailing in muted gray.
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

# _focused_pane: pane id of the attached client's currently-visible pane (skipping a sidebar). Empty if none.
_focused_pane() {
  tmux list-panes -a -F '#{session_attached}	#{window_active}	#{pane_active}	#{@sidebar}	#{pane_id}' 2>/dev/null \
  | awk -F'\t' '$1>=1 && $2==1 && $3==1 && $4!=1 {print $5; exit}' || true
}

# _jump: switch the client to the agent pane identified by target ($1).
_jump() {
  [ -n "${1:-}" ] || return 0
  tmux switch-client -t "$1"
  tmux select-window -t "$1"
  tmux select-pane   -t "$1"
}

# __fzf: the picker — runs *inside* pick's popup. Enter jumps (and closes the popup).
__fzf() {
  local rows sel
  rows=$(_agents_status)
  [ -n "$rows" ] || { tmux display-message "No agents running"; return 0; }
  sel=$(printf '%s\n' "$rows" | _fmt \
        | "$FZF" --ansi --no-sort --delimiter='\t' --with-nth=2 --prompt='agent> ' \
        | cut -f1)
  [ -n "$sel" ] && _jump "$sel"
}

# pick: centered popup (matches tmux-fzf-sessions.sh / tmux-fzf-windows.sh). Height = agents + 5.
_pick() {
  local n
  n=$(python3 "$STATE" panes 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || { "$(dirname "$0")/tmux-notify.sh" "No agents running"; return 0; }
  tmux display-popup -E -w 70% -h "$((n + 5))" -T ' agents ' "'$0' __fzf" || true
}

# count: "✳ <busy>/<total>" for status-right, busy = working|compacting; prints nothing when none run so the
# bar stays clean (the glyph lives here, so the empty state leaves no orphan mark). Repaints the dots from
# the same rows in the background — the #() job must print and exit fast.
_count() {
  local rows total busy
  rows=$(_agents_status)
  ( _paint "$rows" >/dev/null 2>&1 & )
  [ -n "$rows" ] || return 0
  total=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
  busy=$(printf '%s\n' "$rows" | grep -cE '^(working|compacting)	' || true)
  printf '✳ %s/%s' "$busy" "$total"
}

# _dot: rose-pine colored glyph for a status, as tmux #[..] style directives (NOT raw ANSI) so
# window-status-format draws it via #{E:@agent_dot}. The leading space is uncolored so the dot separates
# cleanly from the window name it trails.
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

# paint [rows]: set each window's @agent_dot to its most urgent agent's dot (errored > waiting > compacting >
# working > unread > read), unset it where no agent runs. Takes pre-fetched rows (count) or reads its own.
# Diffed against each window's CURRENT @agent_dot (one list-windows), so a steady state repaints nothing and
# only a real transition redraws — and diffing live tmux state (not a cache) means overlapping runs or a
# server restart can't leave a stale dot: the next run always converges.
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

# _prune: delete hook flag files whose pane no longer exists — left when a session ends by kill/crash so
# SessionEnd never fired; a stale one would mis-flag a new pane reusing the id after a server restart.
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

# _refresh_agents: the pane-title-changed path. A working agent's spinner rewrites its title several
# times/second; the mkdir lock coalesces a burst into one refresh ~0.4s later, and _paint's diff keeps a
# steady spinner at zero redraws.
_refresh_agents() {
  local lock="/tmp/agent-sidebar-refresh-${UID:-0}.lock"
  mkdir "$lock" 2>/dev/null || return 0                                 # a refresh is already scheduled → coalesce
  ( trap 'rmdir "$lock" 2>/dev/null' EXIT; sleep 0.4; _refresh ) &
}

# mark-read: you switched into a pane (keyboard nav, tab/session switch, or click) — if it's an agent that
# finished while you were away (@agent_unread, set by the detector), it's now seen: gray ● → ○. Refreshes
# regardless, so a transition on the pane you land in repaints.
_mark_read() {
  local pid
  pid=$(_focused_pane)
  [ -n "$pid" ] && tmux set-option -pu -t "$pid" @agent_unread 2>/dev/null
  _refresh
}

case "${1:-pick}" in
  pick)           _pick ;;
  __fzf)          __fzf ;;                                   # internal: invoked inside the popup
  count)          _count ;;
  paint)          _paint ;;
  agent-panes)    [ -n "${2:-}" ] && python3 "$STATE" panes "$2" 2>/dev/null ;;
  refresh)        _refresh ;;
  refresh-agents) _refresh_agents ;;
  mark-read)      _mark_read ;;
  *) echo "tmux-agents: unknown mode '${1}' (expected: pick|count|paint|agent-panes)" >&2; exit 1 ;;
esac
