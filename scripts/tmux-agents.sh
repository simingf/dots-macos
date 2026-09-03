#!/usr/bin/env bash
# tmux-agents.sh — find, jump to, count, and watch coding-agent panes across all tmux sessions.
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
# read (`mark-read`). Dots: yellow ●=working, blue ●=needs answer, red ●=errored (StopFailure), gray ●=done-unread,
# gray ○ (hollow)=read, purple ●=compacting; a centered · marks a tab with no agent.
#
# Modes:
#   pick    (default)  fzf popup → switch to the chosen agent pane
#   count              "<working>/<total>" for the status bar (prints nothing when none run)
#   sidebar            toggle a live, clickable agent panel in the current window (bind A)
#   panel              the panel UI itself — runs inside the sidebar pane (double-click/enter jumps)
#   jump <target>      switch to an agent pane by target (used by the picker and panel binds)
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

# Fixed sidebar width (cols). tmux redistributes pane sizes when the client's terminal resizes (e.g.
# plugging/unplugging a monitor), which would grow the sidebar; a client-resized hook calls `fix-width`
# to snap it back to this. Single source of truth for _sidebar_open (-l) and _fix_width (-x).
SIDEBAR_COLS=24

# grep matches the braille spinner range in AGENT_RE below. C / C.UTF-8 ship a
# minimal collation, so GNU grep errors ("Invalid collation character") on the
# multibyte range and _list skips every pane — agents never show. If the ambient
# locale can't handle the range (e.g. a dev box defaulting to C.UTF-8), switch to
# a full UTF-8 locale. No-op where it already works (macOS, en_US.UTF-8 boxes).
if ! printf '⠿' | grep -qE '[⠀-⣿]' 2>/dev/null; then
    export LC_ALL=en_US.UTF-8
fi

# What marks a pane as an agent — matched against the OSC title only. Braille = a working spinner
# frame (generic across agents); "Claude Code"/✳✶✻✽ = an idle agent. Add markers here for other agents.
AGENT_RE='[⠀-⣿]|Claude Code|[✳✶✻✽]'

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
  # __lines pre-fetches ONE list-panes for the whole render and hands it in via $_PANES (a 12-field
  # superset), so we project the 5 fields we need from it instead of a second tmux round-trip. Standalone
  # callers (count/pick/__fzf) leave $_PANES unset and we fetch our own. Either way the rest is shared.
  if [ -n "${_PANES:-}" ]; then
    agents=$(printf '%s\n' "$_PANES" | awk -F'\t' '{print $12"\t"$2":"$3"."$6"\t"$10"\t"$5"\t"$11}')
  else
    agents=$(tmux list-panes -a -F '#{pane_title}	#{session_name}:#{window_index}.#{pane_index}	#{window_activity}	#{window_name}	#{pane_id}' 2>/dev/null)
  fi
  agents=$(printf '%s\n' "$agents" | grep -E "^[^	]*(${AGENT_RE})") || true
  [ -n "$agents" ] || return 0
  printf '%s\n' "$agents" | grep -E  '^[⠀-⣿]' | awk -F'\t' '{print "0\t"$2"\t"$3"\t"$4"\t"$1"\t"$5}'   # braille prefix → working
  printf '%s\n' "$agents" | grep -vE '^[⠀-⣿]' | awk -F'\t' '{print "1\t"$2"\t"$3"\t"$4"\t"$1"\t"$5}'   # else idle/waiting
}

# _sorted: working agents first, then idle; within a group, most-recently-active first.
_sorted() { _list | sort -t$'\t' -k1,1n -k3,3nr; }

# _fmt: _sorted rows → "target <TAB> ● title  session:window" for fzf (col1 = jump target, hidden by
# --with-nth=2; col2 = the ● working / ○ idle line shown). Shared by the picker and the panel.
_fmt() {
  awk -F'\t' '{ g=($1==0?"●":"○"); split($2,t,":"); printf "%s\t%s  %s  \033[38;5;244m%s:%s\033[0m\n", $2, g, $5, t[1], $4 }'
}

# _sock: the fzf listen-socket path for a sidebar pane ($1 = pane id like %25). Deterministic (no
# bookkeeping) and per-uid/per-pane; short under /tmp to stay within the ~104-char sun_path limit.
_sock() { printf '/tmp/agent-sidebar-%s-%s.sock' "${UID:-0}" "${1//[^0-9]/}"; }

# _statef: the status file Claude Code's agent-status.sh writes for a pane ($1 = pane id). Both sides
# derive the same path, so the sidebar reads what the hook wrote (working is title-derived, not here).
_statef() { printf '/tmp/agent-status-%s-%s' "${UID:-0}" "${1//[^0-9]/}"; }

# _focused_pane: "<pane_id>\t<sess:win.pane>" of the attached client's currently-visible pane (skipping the
# sidebar itself). Empty if none. Drives the "active agent" gray highlight and mark-read.
_focused_pane() {
  tmux list-panes -a -F '#{session_attached}	#{window_active}	#{pane_active}	#{@agent_sidebar}	#{pane_id}	#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
  | awk -F'\t' '$1>=1 && $2==1 && $3==1 && $4!=1 {print $5"\t"$6; exit}' || true
}

# _agents_status: augment _sorted with each agent's status word — "status\ttarget\twindow\tpane_id".
# working = live braille spinner; otherwise the Claude-hook state file (waiting/unread/read), default read.
# Consumed by __lines for BOTH the per-tab dot and the agents section, so they never disagree.
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
    printf '%s\t%s\t%s\t%s\n' "$st" "$target" "$window" "$pane_id"
  done
}

# _jump: switch the client to the agent pane identified by target ($1). Called by the picker + panel.
_jump() {
  [ -n "${1:-}" ] || return 0
  tmux switch-client -t "$1"
  tmux select-window -t "$1"
  tmux select-pane   -t "$1"
}

# _activate: panel click/enter dispatch — a session token (s:) switches sessions, a window token
# (w:<session>:<index>) switches to that session AND selects the tab (select-window alone only changes the
# target session's active window, not the client's session), an agent token (a:) jumps to that pane, a
# label ('-') no-ops.
_activate() {
  local wt
  case "${1:-}" in
    s:?*) tmux switch-client -t "${1#s:}" ;;
    w:?*) wt="${1#w:}"; tmux switch-client -t "${wt%%:*}"; tmux select-window -t "$wt" ;;
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
        | "$FZF" --ansi --no-sort --delimiter='\t' --with-nth=2 --prompt='agent> ' \
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

# __lines: NUL-delimited, colored rows for the panel. "spaces" section: each space (name only, no dot)
# with EVERY tab nested under it; a tab's dot shows the status of the agent in it — yellow=working /
# red=needs answer / blue=done-unread / gray=read — or a centered · when the tab has no agent. The
# attached space's active tab gets a full-width gray background (the "you are here" tab). "agents"
# section: the flat agent list, dot = status; the agent whose pane you're focused in gets the gray
# background too. Attached/active/focus are all global, so the output is identical in every sidebar and
# `refresh` can dedup on one cksum. Field 1 = dispatch token (s: / w: / a: / '-'), field 2 = shown text.
__lines() {
  local R=$'\033[0m' MUTE=$'\033[38;2;110;106;134m' TXT=$'\033[1;38;2;224;222;244m' \
        FOAM=$'\033[38;2;156;207;216m' GOLD=$'\033[38;2;246;193;119m' LOVE=$'\033[38;2;235;111;146m' \
        IRIS=$'\033[38;2;196;167;231m'
  local P agents BG=$'\033[48;2;38;35;58m'
  # ONE list-panes drives the entire render — the space tree, window tree, focus highlight, sidebar height,
  # and the agent list all derive from this in awk, instead of ~7 separate tmux round-trips (2× list-sessions,
  # list-windows -a, per-session list-windows, and 3× list-panes via _focused_pane/_list/H) that dominated
  # refresh latency. Every window/session has ≥1 pane, so list-panes -a covers the full tree. 12 fields,
  # TAB-separated, pane_title last (it may contain spaces): attached, session, win_idx, win_active, win_name,
  # pane_idx, pane_active, @sidebar, pane_height, win_activity, pane_id, pane_title.
  P=${__PANES_FROZEN:-$(tmux list-panes -a -F '#{session_attached}	#{session_name}	#{window_index}	#{window_active}	#{window_name}	#{pane_index}	#{pane_active}	#{@agent_sidebar}	#{pane_height}	#{window_activity}	#{pane_id}	#{pane_title}' 2>/dev/null)}   # $__PANES_FROZEN lets a test inject a fixed snapshot for a deterministic byte-diff
  # Order the flat agent list in the SAME space/tab order as the tree (session name alpha, then window
  # index, then pane index) so each agent lines up with its tab. Decorate-sort-undecorate on the target
  # (field 2 = session:window.pane); zero-pad the indices so the lexical sort is numeric. Detection +
  # status precedence stay in the proven _agents_status/_list pipeline (one place to fix status bugs);
  # the render awk below only lays it out.
  _PANES="$P"                                                            # _agents_status → _sorted → _list reads this instead of re-querying tmux
  agents=$(_agents_status | awk -F'\t' '{
      c=index($2,":"); s=substr($2,1,c-1); r=substr($2,c+1); d=index(r,".");
      printf "%s\t%09d\t%09d\t%s\n", s, substr(r,1,d-1), substr(r,d+1), $0
    }' | sort -t$'\t' -k1,1 -k2,2 -k3,3 | cut -f4-)
  unset _PANES
  # ONE awk renders the whole panel — replacing the per-session / per-window / per-tab / pad bash loops
  # (each forked awk+sort, and THAT spawn count, not the tmux round-trips, was the refresh cost). Two
  # inputs: pass 1 = the agent list (builds the per-tab dot map + the ordered agent rows), pass 2 = the $P
  # snapshot (space/window tree, focus highlight, sidebar height + counts for the mid-height pad); END emits.
  # To tweak the look later: dotstr() = tab-dot color/glyph, the agents-section loop = agent rows, hl() =
  # the gray "you are here" bar. Output = NUL-delimited "token<TAB>text"; identical across sidebars
  # (attached/active/focus are global), so `refresh` dedups on one cksum. token: s:/w:/a: dispatch or '-'.
  awk -F'\t' \
      -v cols="$SIDEBAR_COLS" -v R="$R" -v BG="$BG" -v MUTE="$MUTE" -v TXT="$TXT" \
      -v FOAM="$FOAM" -v GOLD="$GOLD" -v LOVE="$LOVE" -v IRIS="$IRIS" '
    function dotstr(st) {                            # tab dot = most-urgent agent status in that tab
      if (st=="working")    return GOLD "●" R        # working = yellow
      if (st=="waiting")    return FOAM "●" R        # needs answer = blue
      if (st=="errored")    return LOVE "●" R        # errored = red
      if (st=="compacting") return IRIS "●" R        # compacting = purple
      if (st=="unread")     return MUTE "●" R        # done, unread = filled gray
      if (st=="read")       return MUTE "○" R        # done, read = hollow gray
      return MUTE "·" R                              # no agent in this tab → centered middot
    }
    function hl(t, vis,   pad) {                     # wrap a row in a full-width gray bg (active tab / focused agent)
      gsub(Rre, R BG, t)                             # re-assert bg after every internal reset so fg changes do not clear it
      pad = cols - vis; if (pad < 0) pad = 0
      return BG t sprintf("%*s", pad, "") R          # pad to sidebar width (fzf truncates any overshoot)
    }
    BEGIN {
      Rre = R; sub(/\[/, "\\[", Rre)                 # escape the [ in ESC[0m so gsub matches the reset literally
      rank["read"]=0; rank["unread"]=1; rank["working"]=2; rank["compacting"]=3; rank["waiting"]=4; rank["errored"]=5
    }
    # pass 1 — agent list: status <TAB> target(sess:win.pane) <TAB> window <TAB> pane_id, pre-sorted sess/win/pane
    FNR==NR {
      if ($0 == "") next
      tab = $2; sub(/\.[0-9]+$/, "", tab)            # tab key = session:window (drop .pane)
      if (!(tab in tbest) || rank[$1] >= trank[tab]) { tbest[tab]=$1; trank[tab]=rank[$1] }   # most-urgent status wins
      na++; ast[na]=$1; atgt[na]=$2; awin[na]=$3     # ordered rows for the agents section
      next
    }
    # pass 2 — panes (12 fields), pre-sorted sess/win/pane so first-seen order = sessions alpha, windows ascending
    {
      if ($0 == "") next
      if (foc=="" && $1>=1 && $4==1 && $7==1 && $8!=1) foc = $2":"$3"."$6   # focused, non-sidebar pane
      if (H=="" && $8==1) H = $9                                            # a sidebar pane height
      if (!($2 in seenS)) { seenS[$2]=1; sord[++nS]=$2; satt[$2]=$1 }       # sessions in order
      k = $2":"$3
      if (!(k in seenW)) { seenW[k]=1; nW++; word[$2]=word[$2] (word[$2]==""?"":" ") $3; wact[k]=$4; wname[k]=$5 }  # windows per session
    }
    END {
      for (i=1; i<=nS; i++) {                        # spaces, each with its tabs nested
        s = sord[i]
        printf "s:%s\t%s%s%s%c", s, MUTE, s, R, 0    # session row: name only, no dot; muted (tabs below are the emphasis, matching the agents section)
        m = split(word[s], wl, " ")
        for (j=1; j<=m; j++) {
          idx = wl[j]; k = s":"idx
          disp = dotstr((k in tbest) ? tbest[k] : "") " " TXT wname[k] R   # tab name bright (emphasized), like the agents section; no indent
          vis = 2 + length(wname[k])                   # dot + 1 space + name
          if (satt[s] >= 1 && wact[k] == 1) disp = hl(disp, vis)   # attached space active tab → gray bg
          printf "w:%s:%s\t%s%c", s, idx, disp, 0
        }
      }
      if (H == "") H = 0                             # anchor the agents section ~mid-height with blank spacers
      pad = int(H/2) - nS - nW - 2; if (pad < 1) pad = 1
      for (i=1; i<pad; i++) printf "-\t%c", 0        # (pad-1) blanks; the rule takes the row at ~mid-height
      rule = ""; for (i=0; i<cols; i++) rule = rule "─"
      printf "-\t%s%s%s%c", MUTE, rule, R, 0         # horizontal border above the agents section
      printf "-\t%sagents%s%c", MUTE, R, 0           # section label (no-op on click)
      for (i=1; i<=na; i++) {                        # flat agent list, dot = status
        st = ast[i]; glyph = "●"; col = MUTE
        if      (st=="working")    col = GOLD
        else if (st=="waiting")    col = FOAM
        else if (st=="errored")    col = LOVE
        else if (st=="compacting") col = IRIS
        else if (st=="read")       glyph = "○"       # read = hollow gray ring; unread/other = filled gray
        disp = col glyph R " " TXT awin[i] R                       # dot + tab; no indent
        vis = 2 + length(awin[i])                                  # dot + 1 space + tab name
        if (foc != "" && atgt[i] == foc) disp = hl(disp, vis)     # focused agent → gray bg
        printf "a:%s\t%s%c", atgt[i], disp, 0
      }
    }
  ' <(printf '%s\n' "$agents") <(printf '%s\n' "$P" | sort -t$'\t' -k2,2 -k3,3n -k6,6n)
}

# panel: the live, clickable sidebar UI — runs inside the sidebar pane. A "sessions" header over the
# session/tab tree, an "agents" divider over the agent list. A single left-click (or enter) switches
# session (s:) / selects a tab (w:) / jumps to the agent pane (a:) WITHOUT closing the panel. The gray
# "you are here" backgrounds are rendered by __lines itself (active tab + focused agent), so fzf's own
# current-line highlight is disabled (bg+:-1, no --highlight-line). Refresh is event-driven, not polled
# (no 2s flash): start:reload seeds the list once, then tmux hooks POST a reload into --listen ($sock)
# via `refresh` on any session/tab/focus/agent-status change.
_panel() {
  # Fancy visual flags need a recent fzf (--no-input, --listen; ~0.53+). Debian ships 0.44, which aborts
  # on an unknown flag — killing the pane. Probe --help and add only what's supported so the sidebar still
  # renders on old fzf (without --listen it just falls back to no live refresh — the hooks no-op).
  local extra=() help sock; help=$("$FZF" --help 2>&1)
  case "$help" in *--no-input*) extra+=(--no-input) ;; esac
  case "$help" in *--listen*) sock=$(_sock "${TMUX_PANE:-}"); rm -f "$sock" 2>/dev/null; extra+=(--listen="$sock") ;; esac
  "$FZF" --read0 --ansi --layout=reverse --info=hidden \
      ${extra[@]+"${extra[@]}"} --pointer='' --marker='' --ellipsis='' \
      --header='sessions ' --header-first --delimiter='\t' --with-nth=2 \
      --color='bg+:-1,fg+:-1:regular,gutter:-1,header:#6e6a86,pointer:-1' \
      --bind "start:reload('$0' __lines)" \
      --bind "left-click:execute-silent('$0' activate {1})+reload('$0' __lines)" \
      --bind "enter:execute-silent('$0' activate {1})+reload('$0' __lines)" \
      >/dev/null 2>&1 || true
}

# _live_socks: the fzf listen-socket path of every open sidebar that has one (one per line).
_live_socks() {
  local pid s
  tmux list-panes -a -F '#{@agent_sidebar}	#{pane_id}' 2>/dev/null \
  | awk -F'\t' '$1==1 {print $2}' \
  | while IFS= read -r pid; do s=$(_sock "$pid"); [ -S "$s" ] && printf '%s\n' "$s"; done
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

# refresh: push a flash-free reload into every open sidebar — but only when the panel's rendered content
# actually changed. We dedup on a cksum of __lines (identical across sidebars, since the list is now
# pane-independent): a stored sig equal to the current one means nothing visible changed, so we skip the
# POST entirely. reload-sync swaps the list atomically (no clear-then-repaint flicker). Wired to the
# structural hooks (immediate) and, via _refresh_agents, pane-title-changed. No-op when no sidebar has a
# live socket, or curl/fzf --listen is unavailable. Prunes orphaned status files first (any refresh trigger).
_refresh() {
  _prune
  command -v curl >/dev/null 2>&1 || return 0
  local socks sig sigf cf tmp sock; socks=$(_live_socks); [ -n "$socks" ] || return 0
  cf="/tmp/agent-sidebar-content-${UID:-0}"; sigf="/tmp/agent-sidebar-sig-${UID:-0}"; tmp="$cf.$$"
  # Render the panel ONCE into a file (bash can't hold the NUL-delimited output in a var), cksum it for the
  # dedup, then have each sidebar's reload just `cat` the file. Previously the reload ran `'$0' __lines`,
  # so __lines (~0.15s) ran a SECOND time on the fzf side — that's what made the active highlight lag ~0.5s
  # after a click. Now the fzf side just cats a ready file, so the highlight updates as soon as one render
  # finishes. $$-suffixed temp + atomic mv so parallel refreshes (several hooks fire per switch) don't clash.
  __lines > "$tmp" 2>/dev/null
  sig=$(cksum < "$tmp")
  if [ "$sig" = "$(cat "$sigf" 2>/dev/null)" ]; then rm -f "$tmp"; return 0; fi   # nothing visible changed → no reload
  printf '%s' "$sig" > "$sigf"
  mv -f "$tmp" "$cf"                                                    # atomic publish before any reader cats it
  printf '%s\n' "$socks" | while IFS= read -r sock; do
    curl -s --unix-socket "$sock" "http://localhost/" --data-binary "reload-sync(cat '$cf')" >/dev/null 2>&1 || true
  done
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

# mark-read: you switched into a pane (keyboard nav, tab/session switch, or click). First `_deflect` — if you
# landed on the sidebar, bounce to the tab's last real pane so it's never keyboard-focused; running it here
# (not as its own hook) covers window/session switches too, since those don't fire after-select-pane, and it
# means _focused_pane below reads the real pane you end up on. Then, if that pane is an agent showing "unread"
# (blue), flip it to "read" (gray), and refresh so its dot and the follow-focus gray highlight update. Only
# touches unread (leaves working/waiting), and refreshes regardless so the highlight tracks focus into any pane.
_mark_read() {
  local fp pid f
  _deflect                                                             # bounce off the sidebar before reading focus
  fp=$(_focused_pane); pid=${fp%%$'\t'*}
  if [ -n "$pid" ]; then
    f=$(_statef "$pid")
    [ "$(cat "$f" 2>/dev/null || true)" = unread ] && printf 'read' > "$f"
  fi
  _refresh
}

# _deflect: bounce focus off the agent sidebar so it's never the *keyboard*-focused pane. The panel is
# click-only (mouse events route to the pane under the cursor regardless of which pane is active), so if a
# pane switch lands ON the sidebar — keyboard nav (select-pane -L into the leftmost pane) or a click on a
# no-op row — we redirect to the window's most-recently-active real pane. Wired to after-select-pane. The
# check reads the CURRENT attached active pane (not the pane the hook fired for), so a click that already
# jumped elsewhere via `activate` leaves a non-sidebar pane active and this no-ops — never fighting the jump.
_deflect() {
  local row win target
  row=$(tmux list-panes -a -F '#{session_attached}	#{window_active}	#{pane_active}	#{@agent_sidebar}	#{window_id}' 2>/dev/null \
    | awk -F'\t' '$1>=1 && $2==1 && $3==1 {print $4"|"$5; exit}')
  [ "${row%%|*}" = 1 ] || return 0                                     # active pane isn't the sidebar → nothing to do
  win=${row#*|}
  tmux select-pane -t "$win" -l 2>/dev/null                           # most-recently-active pane in the tab
  # last-pane can be unset (sidebar was the first pane ever selected) or itself the sidebar — fall back to the
  # first real pane so we always leave the sidebar.
  if [ "$(tmux display-message -p -t "$win" '#{@agent_sidebar}' 2>/dev/null)" = 1 ]; then
    target=$(tmux list-panes -t "$win" -F '#{@agent_sidebar}	#{pane_id}' 2>/dev/null | awk -F'\t' '$1!="1"{print $2; exit}')
    [ -n "$target" ] && tmux select-pane -t "$target" 2>/dev/null || true
  fi
}

# _sidebar_open: create the panel as a fixed-width ($SIDEBAR_COLS) LEFT split in the current window (tagged @agent_sidebar,
# focus stays put via -d). No-op if this window already has one — so `prefix c` can call it blindly.
_sidebar_open() {
  tmux list-panes -F '#{@agent_sidebar}' | grep -q '^1$' && return 0
  local pane
  pane=$(tmux split-window -h -b -l "$SIDEBAR_COLS" -c "$HOME" -d -P -F '#{pane_id}' "'$0' panel") || return 0
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

# _fix_width: snap every open sidebar back to $SIDEBAR_COLS. Wired to the client-resized hook so plugging
# or unplugging a monitor (which resizes the client's terminal and makes tmux redistribute pane widths)
# doesn't grow/shrink the sidebar. Idempotent — resizing a pane already at the target is a no-op.
_fix_width() {
  tmux list-panes -a -F '#{@agent_sidebar}	#{pane_id}' 2>/dev/null \
  | awk -F'\t' '$1==1 {print $2}' \
  | while IFS= read -r pid; do tmux resize-pane -t "$pid" -x "$SIDEBAR_COLS" 2>/dev/null || true; done
}

# reap: close window $1 when its only remaining pane(s) are the sidebar — so exiting your last real
# pane closes the tab instead of leaving a lone sidebar. Wired to window-layout-changed in .tmux.conf.
_reap() {
  local win="${1:-}"
  [ -n "$win" ] || return 0
  # Close the window only when the agent sidebar is the SOLE surviving pane, so exiting your last real pane
  # closes the tab instead of leaving a lone sidebar. Evaluated in a single awk pass over one list-panes:
  # kill iff there is ≥1 pane, ≥1 sidebar pane, and 0 real panes. This can NEVER kill a window that still
  # holds a real pane — it avoids the previous two-call race (a second list-panes returning empty during
  # layout churn read as "0 real panes" → wrongly nuked a live tab).
  tmux list-panes -t "$win" -F '#{@agent_sidebar}' 2>/dev/null | awk '
    { n++; if ($0 == "1") sb++; else real++ }
    END { exit (n > 0 && sb > 0 && real == 0) ? 0 : 1 }' \
    && tmux kill-window -t "$win" 2>/dev/null || true
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
  refresh)      _refresh ;;           # internal: invoked by the structural tmux hooks (live sidebar reload)
  refresh-agents) _refresh_agents ;;  # internal: invoked by the pane-title-changed hook (debounced agent-state reload)
  mark-read)    _mark_read ;;         # internal: invoked by the pane-focus-in hook (unread → read + follow focus)
  deflect)      _deflect ;;           # internal: called by _mark_read on every focus change (bounce focus off the sidebar); also runnable standalone
  fix-width)    _fix_width ;;         # internal: invoked by the client-resized hook (pin sidebar width)
  reap)         _reap "${2:-}" ;;     # internal: invoked by the window-layout-changed hook
  *) echo "tmux-agents: unknown mode '${1}' (expected: pick|count|sidebar)" >&2; exit 1 ;;
esac
