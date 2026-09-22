#!/usr/bin/env bash
# tmux-agents.sh — find, jump to, count, and surface coding-agent status across all tmux sessions.
#
# Agent status is surfaced in the NATIVE top status bar: `paint` writes each window's most-urgent agent
# status into its @agent_dot option, which window-status-format draws as a colored dot after the tab name.
# (The old clickable left-split agent sidebar this drove is retired — its code lives in
# archive/agent-sidebar/tmux-agents-sidebar.sh; see that folder's README to restore it.)
#
# Detection: an interactive agent sets its terminal title via OSC, captured into #{pane_title} — a braille
# spinner frame while working ("⠂ <task summary>"), a non-spinner marker otherwise. We match that title to
# find agent panes and to detect "working". Requires a UTF-8 LC_CTYPE (inherited from the tmux client) so
# grep matches the braille block — every real ghostty/tmux session provides one.
#
# Finer status (needs-answer / done-unread / read / compacting) can't be read from the title — it comes
# from Claude Code lifecycle hooks writing /tmp/agent-status-<uid>-<pane> (see .claude/hooks/agent-status.sh):
# Stop → unread (or read if you're already looking), AskUserQuestion/Notification → waiting, PreCompact →
# compacting (PostCompact/UserPromptSubmit clear it), SessionEnd → removed. pane-focus-in flips unread →
# read (`mark-read`). Dots: gold ●=working, foam ●=needs answer, love ●=errored (StopFailure), gray ●=done-unread,
# gray ○ (hollow)=read, iris ●=compacting; a window with no agent gets no dot.
#
# Modes:
#   pick    (default)  fzf popup → switch to the chosen agent pane
#   count              "<working>/<total>" for the status bar (prints nothing when none run)
#   paint              write each window's @agent_dot for the top status bar (also auto-run from refresh)
#
# No `set -e`/`pipefail`: every function here is fire-and-forget tmux glue run from `run-shell -b` hooks
# *during* structural churn, when a `tmux list-*` target can be transiently gone. pipefail would turn that
# into a failed pipeline and set -e would abort before the code's own `|| return 0` / `${x:-0}` guards run —
# surfacing as a pane-blanking "'…tmux-agents.sh …' returned 1" overlay. Keep nounset (the code guards for it).
set -u

# Prefer a vendored fzf over an old system one: Debian's apt fzf (0.44) is too old
# for the panel's flags, and tmux resolves bare `fzf` from the server PATH, which on
# non-login setups misses ~/.local/bin. Pick the vendored one explicitly when present.
FZF="$HOME/.local/bin/fzf"; [ -x "$FZF" ] || FZF=fzf

# grep matches the braille spinner range in AGENT_RE below. C / C.UTF-8 ship a
# minimal collation, so GNU grep errors ("Invalid collation character") on the
# multibyte range and _list skips every pane — agents never show. If the ambient
# locale can't handle the range (e.g. a dev box defaulting to C.UTF-8), switch to
# a full UTF-8 locale. No-op where it already works (macOS, en_US.UTF-8 boxes).
if ! printf '⠿◐' | grep -qE '[⠀-⣿◐-◓]' 2>/dev/null; then
    export LC_ALL=en_US.UTF-8
fi

# What marks a pane as an agent — matched against the OSC title only. Braille (⠀-⣿) = a working spinner
# on macOS; quarter-circles (◐-◓) = a working spinner on Linux; "Claude Code"/✳✶✻✽ = an idle agent.
AGENT_RE='[⠀-⣿◐-◓]|Claude Code|[✳✶✻✽]'

# _list: one row per agent pane — state <TAB> target <TAB> activity <TAB> window <TAB> title
# state: 0 = working (title starts with a braille spinner frame), 1 = idle/waiting.
# window = tmux window (tab) name; title = the task summary the agent sets. TAB-delimited (titles keep
# spaces). The match tests the TITLE only, so a window merely *named* "node"/"agent" never false-matches.
_list() {
  # One list-panes, then whole-stream greps instead of 2 greps PER pane (which scaled with pane count and
  # dominated the sidebar's refresh latency). Title goes first so the marker regex anchors to the title (not
  # window names); one grep filters to agent panes, two more split working (braille prefix) vs idle. awk only
  # REORDERS fields back to state/target/activity/window/title/pane_id — no multibyte matching, since this
  # awk build mishandles the braille range (matches everything), so detection stays in grep.
  local agents
  # A caller may pre-fetch ONE `list-panes -a` (a 12-field superset) and hand it in via $_PANES, so we
  # project the 5 fields we need from it instead of a second tmux round-trip. (The sidebar's __lines used
  # this; it's now in archive/agent-sidebar/, so today all callers leave $_PANES unset and we fetch our own.)
  if [ -n "${_PANES:-}" ]; then
    agents=$(printf '%s\n' "$_PANES" | awk -F'\t' '{print $12"\t"$2":"$3"."$6"\t"$10"\t"$5"\t"$11}')
  else
    agents=$(tmux list-panes -a -F '#{pane_title}	#{session_name}:#{window_index}.#{pane_index}	#{window_activity}	#{window_name}	#{pane_id}' 2>/dev/null)
  fi
  agents=$(printf '%s\n' "$agents" | grep -E "^[^	]*(${AGENT_RE})") || true
  [ -n "$agents" ] || return 0
  printf '%s\n' "$agents" | grep -E  '^[⠀-⣿◐-◓]' | awk -F'\t' '{print "0\t"$2"\t"$3"\t"$4"\t"$1"\t"$5}'   # spinner prefix → working
  printf '%s\n' "$agents" | grep -vE '^[⠀-⣿◐-◓]' | awk -F'\t' '{print "1\t"$2"\t"$3"\t"$4"\t"$1"\t"$5}'   # else idle/waiting
}

# _sorted: working agents first, then idle; within a group, most-recently-active first.
_sorted() { _list | sort -t$'\t' -k1,1n -k3,3nr; }

# _fmt: _agents_status rows → "target <TAB> ● session:window  description" for the picker (col1 = jump target,
# hidden by --with-nth=2; col2 = the shown line). The dot is colored by the SAME status palette as the sidebar
# (working=gold / waiting=foam / errored=love / compacting=iris / unread+read=gray, hollow ○ for read), the
# session:window name is emphasized in bright rose, and the agent's task summary trails in muted gray.
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

# _statef: the status file Claude Code's agent-status.sh writes for a pane ($1 = pane id). Both sides
# derive the same path, so the sidebar reads what the hook wrote (working is title-derived, not here).
_statef() { printf '/tmp/agent-status-%s-%s' "${UID:-0}" "${1//[^0-9]/}"; }

# _focused_pane: "<pane_id>\t<sess:win.pane>" of the attached client's currently-visible pane (skipping the
# sidebar itself). Empty if none. Drives the "active agent" gray highlight and mark-read.
_focused_pane() {
  tmux list-panes -a -F '#{session_attached}	#{window_active}	#{pane_active}	#{@agent_sidebar}	#{pane_id}	#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
  | awk -F'\t' '$1>=1 && $2==1 && $3==1 && $4!=1 {print $5"\t"$6; exit}' || true
}

# _agents_status: augment _sorted with each agent's status word — "status\ttarget\twindow\tpane_id\ttitle".
# working = live braille spinner; otherwise the Claude-hook state file (waiting/unread/read), default read.
# Consumed by _paint (the top-bar per-window dot) and _fmt (the picker), so they never disagree.
_agents_status() {
  local state target activity window title pane_id st sfval
  _sorted | while IFS=$'\t' read -r state target activity window title pane_id; do
    sfval="$(cat "$(_statef "$pane_id")" 2>/dev/null || true)"
    if [ "$sfval" = compacting ]; then st=compacting                # compaction overrides the working spinner
    elif [ "$sfval" = errored ]; then st=errored                    # an API/tool error overrides a stale spinner: on error the title often keeps its last braille frame, so state=0 lingers even though the agent isn't working
    elif [ "$state" = 0 ]; then st=working
    else case "$sfval" in
           waiting) st=waiting ;; unread) st=unread ;; active) st=working ;; *) st=read ;;
         esac
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$target" "$window" "$pane_id" "$title"
  done
}

# _jump: switch the client to the agent pane identified by target ($1). Called by the picker + panel.
_jump() {
  [ -n "${1:-}" ] || return 0
  tmux switch-client -t "$1"
  tmux select-window -t "$1"
  tmux select-pane   -t "$1"
}

# __fzf: the picker — runs *inside* pick's popup. Enter jumps (and closes the popup).
__fzf() {
  local rows sel
  rows=$(_agents_status) || true
  [ -n "$rows" ] || { tmux display-message "No agents running"; return 0; }
  sel=$(printf '%s\n' "$rows" | _fmt \
        | "$FZF" --ansi --no-sort --delimiter='\t' --with-nth=2 --prompt='agent> ' \
        | cut -f1)
  [ -n "$sel" ] && _jump "$sel"
}

# pick: centered popup (matches tmux-fzf-sessions.sh / tmux-fzf-windows.sh). Height = agents + 5.
_pick() {
  local n
  n=$(_list | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || { tmux display-message "No agents running"; return 0; }
  tmux display-popup -E -w 70% -h "$((n + 5))" -T ' agents ' "'$0' __fzf" || true
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

# _dot: rose-pine colored glyph for a per-window agent status, matching the sidebar's dot palette
# (working=gold ● / waiting=foam ● / errored=love ● / compacting=iris ● / unread=gray ● / read=gray ○).
# Emitted as tmux #[..] style directives (NOT raw ANSI) so window-status-format draws it via #{E:@agent_dot}.
# The leading space is uncolored (before the #[fg]) so the dot separates cleanly from the window name it trails.
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

# paint: render a per-window agent-status dot onto the NATIVE top status bar — no pane, no fzf, no socket.
# For each window, compute the most-urgent status of the agents in it (rank ladder below: errored > waiting >
# compacting > working > unread > read) and stash a colored glyph in its @agent_dot option; window-status-format interpolates it
# via #{E:@agent_dot}. Windows with no agent get @agent_dot unset (→ empty → no glyph). Because it's a per-window
# option inside tmux, the "live refresh" is just: set the options, then `refresh-client -S` to redraw the status
# line — none of the sidebar's listen-socket / curl / reload-sync plumbing. Content-deduped on a cksum of the
# window→status map so a steady working spinner (pane-title-changed re-fires several times/sec) repaints zero
# times; only a real status transition redraws. Called at the top of _refresh so it rides every existing
# trigger (structural hooks, the debounced title path, focus mark-read, and the Claude status-file hooks).
_paint() {
  local map sig sigf
  map=$(_agents_status 2>/dev/null | awk -F'\t' '
    BEGIN { rank["read"]=0; rank["unread"]=1; rank["working"]=2; rank["compacting"]=3; rank["waiting"]=4; rank["errored"]=5 }
    { tab=$2; sub(/\.[0-9]+$/, "", tab)                             # target sess:win.pane → window key sess:win
      if (!(tab in best) || rank[$1] >= r[tab]) { best[tab]=$1; r[tab]=rank[$1] } }
    END { for (t in best) print t"\t"best[t] }') || true
  sigf="/tmp/agent-tabs-sig-${UID:-0}"
  sig=$(printf '%s' "$map" | sort | cksum)
  [ "$sig" = "$(cat "$sigf" 2>/dev/null || true)" ] && return 0     # nothing visible changed → no redraw
  printf '%s' "$sig" > "$sigf"
  tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null \
    | while IFS= read -r w; do tmux set-option -wu -t "$w" @agent_dot 2>/dev/null || true; done  # clear stale dots
  printf '%s\n' "$map" | while IFS=$'\t' read -r tab st; do
    [ -n "$tab" ] || continue
    tmux set-option -w -t "$tab" @agent_dot "$(_dot "$st")" 2>/dev/null || true
  done
  tmux refresh-client -S 2>/dev/null || true
}

# _prune: delete status files whose pane no longer exists — orphans left when a session ends by kill/crash
# (VPN-drop API errors, `tmux kill-pane`, etc.) so SessionEnd never fired to clean up. Cheap (one list-panes
# + a glob loop); keeps /tmp tidy and stops a stale file from mis-coloring a new pane that reuses the id
# after a tmux server restart. Matches _statef's digits-only key.
_prune() {
  local live f d
  live=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr -d '%')
  for f in "/tmp/agent-status-${UID:-0}"-*; do
    [ -e "$f" ] || continue                                              # no matches → literal glob, skip
    d=${f##*-}
    printf '%s\n' "$live" | grep -qx "$d" || rm -f "$f"
  done
}

# refresh: repaint the native top status-bar tab dots and prune orphaned status files. Wired to the
# structural hooks (immediate) and, via _refresh_agents, pane-title-changed. (This used to also push a
# reload into every open agent sidebar's fzf socket; that path moved to archive/agent-sidebar/ when the
# sidebar was retired — _paint's own cksum dedup keeps a steady spinner at zero redraws.)
_refresh() {
  _paint
  _prune
}

# _refresh_agents: the pane-title-changed path. A working agent's spinner rewrites its title several
# times/second, but the dot only flips on a working↔idle transition — so re-rendering per frame is pure
# waste. The mkdir lock coalesces a burst of title events into a single refresh ~0.4s later; _refresh's
# dedup then POSTs only if a dot actually changed. Net: steady spinner = 0 reloads, a transition = 1,
# bounded compute, no flash. Structural hooks stay immediate (they don't go through here).
_refresh_agents() {
  local lock="/tmp/agent-sidebar-refresh-${UID:-0}.lock"
  mkdir "$lock" 2>/dev/null || return 0                                 # a refresh is already scheduled → coalesce
  ( trap 'rmdir "$lock" 2>/dev/null' EXIT; sleep 0.4; _refresh ) &
}

# mark-read: you switched into a pane (keyboard nav, tab/session switch, or click). If that pane is an agent
# showing "unread" (done, gray filled ●), flip it to "read" (gray hollow ○) and refresh so its top-bar dot
# updates. Only touches unread (leaves working/waiting), and refreshes regardless so a status transition on
# the pane you land in repaints. (Previously also ran `_deflect` to bounce focus off the sidebar — retired
# with the sidebar; see archive/agent-sidebar/.)
_mark_read() {
  local fp pid f
  fp=$(_focused_pane); pid=${fp%%$'\t'*}
  if [ -n "$pid" ]; then
    f=$(_statef "$pid")
    [ "$(cat "$f" 2>/dev/null || true)" = unread ] && printf 'read' > "$f"
  fi
  _refresh
}

case "${1:-pick}" in
  pick)    _pick ;;
  __fzf)   __fzf ;;      # internal: invoked inside the popup
  count)   _count ;;
  paint)   _paint ;;     # native top-bar tab dots — writes each window's @agent_dot; also auto-run from _refresh
  refresh)      _refresh ;;           # internal: invoked by the structural tmux hooks (repaint top-bar dots)
  refresh-agents) _refresh_agents ;;  # internal: invoked by the pane-title-changed hook (debounced repaint)
  mark-read)    _mark_read ;;         # internal: invoked by the focus hooks (unread → read + repaint)
  *) echo "tmux-agents: unknown mode '${1}' (expected: pick|count|paint)" >&2; exit 1 ;;
esac
