#!/usr/bin/env bash
# Archived agent-sidebar functions — extracted verbatim from scripts/tmux-agents.sh when the
# sidebar was retired in favor of the native top status-bar dots. NOT runnable standalone: these
# reference shared helpers that remain in tmux-agents.sh (_statef, _focused_pane, _jump,
# _agents_status, _list, FZF, AGENT_RE). See README.md in this folder for how to restore.

# --- SIDEBAR_COLS (fixed sidebar width) ---
# Fixed sidebar width (cols). tmux redistributes pane sizes when the client's terminal resizes (e.g.
# plugging/unplugging a monitor), which would grow the sidebar; a client-resized hook calls `fix-width`
# to snap it back to this. Single source of truth for _sidebar_open (-l) and _fix_width (-x).
SIDEBAR_COLS=24

# --- _sock (fzf listen-socket path per sidebar pane) ---
# _sock: the fzf listen-socket path for a sidebar pane ($1 = pane id like %25). Deterministic (no
# bookkeeping) and per-uid/per-pane; short under /tmp to stay within the ~104-char sun_path limit.
_sock() { printf '/tmp/agent-sidebar-%s-%s.sock' "${UID:-0}" "${1//[^0-9]/}"; }

# --- _activate (panel click/enter dispatch) ---
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

# --- __lines / _panel / _live_socks (the sidebar UI + its sockets) ---
# __lines: NUL-delimited, colored rows for the panel. "spaces" section: each space (name only, no dot)
# with EVERY tab nested under it; a tab's dot shows the status of the agent in it — yellow=working /
# red=needs answer / blue=done-unread / gray=read — or a centered · when the tab has no agent. The
# attached space's active tab gets a full-width gray background (the "you are here" tab). "agents"
# section: the flat agent list, dot = status; the agent whose pane you're focused in gets the gray
# background too. Attached/active/focus are all global, so the output is identical in every sidebar and
# `refresh` can dedup on one cksum. Field 1 = dispatch token (s: / w: / a: / '-'), field 2 = shown text.
__lines() {
  local R=$'\033[0m' BOLD=$'\033[1m' MUTE=$'\033[38;2;110;106;134m' TXT=$'\033[1;38;2;224;222;244m' \
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
      -v cols="$SIDEBAR_COLS" -v R="$R" -v BOLD="$BOLD" -v BG="$BG" -v MUTE="$MUTE" -v TXT="$TXT" \
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
      printf "-\t%s%sagents%s%c", BOLD, MUTE, R, 0   # section label, bold (no-op on click)
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
# session/tab tree, an "agents" divider over the agent list. A left-click, double-click, or enter switches
# session (s:) / selects a tab (w:) / jumps to the agent pane (a:) WITHOUT closing the panel. double-click is
# bound explicitly because fzf's default double-click action is `accept`, which exits fzf and closes the
# sidebar pane — an accidental double-click while clicking around would otherwise make the sidebar vanish. The gray
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
      --color='bg+:-1,fg+:-1:regular,gutter:-1,header:#6e6a86:bold,pointer:-1' \
      --bind "start:reload('$0' __lines)" \
      --bind "left-click:execute-silent('$0' activate {1})+reload('$0' __lines)" \
      --bind "double-click:execute-silent('$0' activate {1})+reload('$0' __lines)" \
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

# --- _deflect / _sidebar_open / _csum / _reclaim_layout / _sidebar / _fix_width / _reap ---
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

# _sidebar_open: create the panel as a fixed-width ($SIDEBAR_COLS), full-height split pinned to the window's
# far-left edge (tagged @agent_sidebar, focus stays put via -d). `-f` spans the whole window height and places
# it at the left edge regardless of which pane is focused — without it the split takes only the focused pane's
# area, landing mid-window when you're in a right column. No-op if this window already has one — so `prefix c`
# can call it blindly.
_sidebar_open() {
  tmux list-panes -F '#{@agent_sidebar}' | grep -q '^1$' && return 0
  local pane
  pane=$(tmux split-window -f -h -b -l "$SIDEBAR_COLS" -c "$HOME" -d -P -F '#{pane_id}' "'$0' panel") || return 0
  # If the panel command dies immediately (e.g. fzf too old), the pane is already
  # gone — tag it defensively so a stale pane never surfaces "no such pane".
  [ -n "$pane" ] && tmux set-option -p -t "$pane" @agent_sidebar 1 2>/dev/null
  return 0
}

# _csum: tmux layout_checksum (layout-custom.c) over a layout body — excludes the leading "csum,".
# Same algorithm as tmux-even-columns.sh; needed to re-sign a rewritten layout for select-layout.
_csum() {
  local s=$1 c=0 i ch
  for ((i = 0; i < ${#s}; i++)); do
    printf -v ch '%d' "'${s:i:1}"
    c=$(((c >> 1) + ((c & 1) << 15)))
    c=$(((c + ch) & 0xffff))
  done
  printf '%04x' "$c"
}

# _reclaim_layout: given the live window layout ($1) and the sidebar's numeric pane id ($2), compute the
# layout that should apply AFTER the sidebar column is removed — the remaining top-level columns rescaled
# proportionally to fill the width the sidebar vacated. So closing is width-neutral: even columns stay even,
# unequal columns keep their ratio, no ratchet onto the neighbor. Prints "csum,body" on success. Returns 1
# (prints nothing) on shapes we won't touch — top level not a left/right split, a column with a nested
# left/right split (inner widths would need their own scaling), sidebar column not found, or <2 real columns
# (tmux already fills those correctly) — and the caller then just kills the pane and lets tmux redistribute.
# Pure (no tmux calls), so it's unit-tested via the `__reclaim` mode. Mirrors tmux-even-columns.sh's parser.
_reclaim_layout() {
  local layout=$1 sidebar_id=$2 body root W inner
  body=${layout#*,}                                # strip "csum,"
  case $body in *,0,0\{*\}) ;; *) return 1 ;; esac  # top level must be a left/right split "WxH,0,0{...}"
  root=${body%%\{*}; W=${root%%x*}
  inner=${body#*\{}; inner=${inner%\}}
  # depth-0 comma split into pieces, then regroup into whole column cells (leaf = 4 pieces "WxH,X,Y,id";
  # group/stack = 3 pieces, the Y piece carrying an attached [..]/{..}). Identical to even-columns.
  local -a pieces=() cells=(); local d=0 tok="" i ch
  for ((i = 0; i < ${#inner}; i++)); do
    ch=${inner:i:1}
    case $ch in
      '{' | '[') d=$((d + 1)); tok+=$ch ;;
      '}' | ']') d=$((d - 1)); tok+=$ch ;;
      ,) if ((d == 0)); then pieces+=("$tok"); tok=""; else tok+=$ch; fi ;;
      *) tok+=$ch ;;
    esac
  done
  pieces+=("$tok")
  local n=${#pieces[@]}; i=0
  while ((i < n)); do
    [[ ${pieces[i]:-} == *x* ]] || return 1        # every cell begins with WxH
    local yp=${pieces[i + 2]:-}
    if [[ $yp == *'['* || $yp == *'{'* ]]; then
      cells+=("${pieces[i]},${pieces[i + 1]:-},${pieces[i + 2]:-}"); i=$((i + 3))
    else
      cells+=("${pieces[i]},${pieces[i + 1]:-},${pieces[i + 2]:-},${pieces[i + 3]:-}"); i=$((i + 4))
    fi
  done
  local ncols=${#cells[@]}; ((ncols >= 2)) || return 1
  # classify columns: width, sidebar?, reject a nested left/right split (would need inner scaling)
  local -a cw=() issb=(); local idx c rest id sumr=0 nreal=0 sbfound=0
  for idx in "${!cells[@]}"; do
    c=${cells[idx]}
    [[ $c == *'{'* ]] && return 1
    cw[idx]=${c%%x*}
    if [[ -n $sidebar_id && $c != *'['* ]]; then
      id=${c##*,}
      if [[ $id == "$sidebar_id" ]]; then issb[idx]=1; sbfound=1; continue; fi
    fi
    issb[idx]=0; sumr=$((sumr + ${cw[idx]})); nreal=$((nreal + 1))
  done
  ((sbfound == 1 && nreal >= 2 && sumr > 0)) || return 1
  local avail=$((W - (nreal - 1)))                 # width for nreal columns after nreal-1 separators
  ((avail >= nreal)) || return 1                   # too narrow for a clean tile → punt
  # proportional floor targets, then hand the rounding leftover out one col at a time, left-to-right
  local -a tgt=(); local acc=0
  for idx in "${!cells[@]}"; do
    ((${issb[idx]} == 1)) && continue
    tgt[idx]=$(( ${cw[idx]} * avail / sumr )); ((${tgt[idx]} < 1)) && tgt[idx]=1
    acc=$((acc + ${tgt[idx]}))
  done
  local leftover=$((avail - acc))
  for idx in "${!cells[@]}"; do
    ((leftover > 0)) || break
    ((${issb[idx]} == 1)) && continue
    tgt[idx]=$((${tgt[idx]} + 1)); leftover=$((leftover - 1))
  done
  # rebuild reals-only, re-chaining X from 0; shift every cell in a column (stacks share width+X) via sed
  local -a newcols=(); local cursor=0 w0 x0 xn nc
  for idx in "${!cells[@]}"; do
    ((${issb[idx]} == 1)) && continue
    c=${cells[idx]}; w0=${cw[idx]}; rest=${c#*,}; x0=${rest%%,*}; xn=$cursor
    nc=$(sed -E "s/([,{[]|^)${w0}x([0-9]+),${x0},/\1${tgt[idx]}x\2,${xn},/g" <<<"$c")
    newcols+=("$nc"); cursor=$((xn + ${tgt[idx]} + 1))
  done
  local joined new_body; joined=$(IFS=,; echo "${newcols[*]}"); new_body="${root}{${joined}}"
  printf '%s,%s\n' "$(_csum "$new_body")" "$new_body"
}

# sidebar: TOGGLE the panel — open it (left, via _sidebar_open) or, if this window already has one, close it.
# On close, reclaim the sidebar's width proportionally across the remaining columns (see _reclaim_layout) so
# toggling is width-neutral — no ratchet onto the neighbor, and a mid-session `prefix 0` even-up survives the
# close. Shapes _reclaim_layout won't rewrite fall back to a plain kill (tmux redistributes). Self-heals if you
# closed it manually (`x`/esc). Per-window: a split can only live in one window, so each window tracks its own.
_sidebar() {
  local existing sbid layout newl
  existing=$(tmux list-panes -F '#{pane_id} #{@agent_sidebar}' | awk '$2 == "1" { print $1; exit }')
  if [ -z "$existing" ]; then _sidebar_open; return 0; fi
  sbid=$(printf '%s' "$existing" | tr -d '%')      # layout strings use the bare numeric id, not "%N"
  layout=$(tmux display-message -p '#{window_layout}')
  newl=$(_reclaim_layout "$layout" "$sbid") || newl=""
  tmux kill-pane -t "$existing"
  [ -n "$newl" ] && tmux select-layout "$newl" 2>/dev/null || true
}

# _fix_width: snap every open sidebar back to $SIDEBAR_COLS. Wired to window-resized (monitor plug/unplug)
# and window-layout-changed (a pane closing — e.g. `:qa` from the kk layout — hands its freed width to the
# bordering pane, often the sidebar). Two loop-breakers, because it runs on window-layout-changed and its own
# resize-pane re-fires that hook:
#   1. WIDTH GUARD (termination): only resize a sidebar whose width actually differs from the target. tmux
#      fires window-layout-changed even on a same-size resize-pane, so an unconditional resize here would
#      recurse forever; skipping the no-op is the condition that ends the chain (resize 224→24 fires once
#      more, the next pass sees 24 and issues no resize, so no further event).
#   2. mkdir LOCK + small debounce (coalesce): fold a burst of layout events into one delayed pass and never
#      overlap two runs — same pattern as _refresh_agents. Belt-and-suspenders over the width guard.
_fix_width() {
  local lock="/tmp/agent-sidebar-fixwidth-${UID:-0}.lock"
  mkdir "$lock" 2>/dev/null || return 0                                  # a fix-width pass is already scheduled → coalesce
  (
    trap 'rmdir "$lock" 2>/dev/null' EXIT
    sleep 0.2
    tmux list-panes -a -F '#{@agent_sidebar}	#{pane_id}	#{pane_width}' 2>/dev/null \
    | awk -F'\t' -v w="$SIDEBAR_COLS" '$1==1 && $3+0 != w+0 {print $2}' \
    | while IFS= read -r pid; do tmux resize-pane -t "$pid" -x "$SIDEBAR_COLS" 2>/dev/null || true; done
  ) &
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
