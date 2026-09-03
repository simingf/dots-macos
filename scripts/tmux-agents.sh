#!/usr/bin/env bash
# tmux-agents.sh — find, jump to, count, and watch coding-agent panes across all tmux sessions.
#
# Detection: an interactive agent sets its terminal title via OSC, captured into #{pane_title} — a braille
# spinner frame while working ("⠂ <task summary>"), a non-spinner marker otherwise. We match that title to
# find agent panes and to detect "working". Requires a UTF-8 LC_CTYPE (inherited from the tmux client) so
# grep matches the braille block — every real ghostty/tmux session provides one.
#
# Finer status (needs-answer / done-unread / read) can't be read from the title — it comes from Claude
# Code lifecycle hooks writing /tmp/agent-status-<uid>-<pane> (see .claude/hooks/agent-status.sh): Stop →
# unread (or read if you're already looking), Notification → waiting. pane-focus-in flips unread → read
# (`mark-read`). The sidebar dot colors it: yellow=working, red=needs answer, blue=done-unread, gray=read.
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
SIDEBAR_COLS=20

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
  local target activity window title state pane_id
  tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{window_activity}	#{window_name}	#{pane_title}	#{pane_id}' \
  | while IFS=$'\t' read -r target activity window title pane_id; do
      printf '%s' "$title" | grep -qE "$AGENT_RE" || continue          # agent pane? (match the OSC title only)
      if printf '%s' "$title" | grep -qE '^[⠀-⣿]'; then state=0; else state=1; fi   # braille prefix → working
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$state" "$target" "$activity" "$window" "$title" "$pane_id"
    done
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

# _hl: wrap display text ($1, may contain resets) as a full-width gray-bg row; $2 = its visible column
# width. Re-asserts the bg after every reset so internal fg changes don't clear it, then pads to the
# sidebar width (fzf truncates any overshoot, so the bar fills the pane). Used for active tab + active agent.
_hl() {
  local R=$'\033[0m' BG=$'\033[48;2;38;35;58m' d pad
  d="${BG}${1//$R/$R$BG}"
  pad=$(( SIDEBAR_COLS - ${2:-0} )); [ "$pad" -gt 0 ] || pad=0
  printf '%s%*s%s' "$d" "$pad" '' "$R"
}

# _agents_status: augment _sorted with each agent's status word — "status\ttarget\twindow\tpane_id".
# working = live braille spinner; otherwise the Claude-hook state file (waiting/unread/read), default read.
# Consumed by __lines for BOTH the per-tab dot and the agents section, so they never disagree.
_agents_status() {
  local state target activity window title pane_id st
  _sorted | while IFS=$'\t' read -r state target activity window title pane_id; do
    if [ "$state" = 0 ]; then st=working
    else case "$(cat "$(_statef "$pane_id")" 2>/dev/null || true)" in
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
        FOAM=$'\033[38;2;156;207;216m' GOLD=$'\033[38;2;246;193;119m' LOVE=$'\033[38;2;235;111;146m'
  local att name widx wact wname disp vis tst tdot agents st target window pane_id acolor sess focus foctarget
  focus=$(_focused_pane); foctarget=${focus#*$'\t'}; [ "$foctarget" = "$focus" ] && foctarget=""
  agents=$(_agents_status)
  tmux list-sessions -F '#{session_attached}	#{session_name}' 2>/dev/null | sort -t$'\t' -k2,2 | while IFS=$'\t' read -r att name; do
    printf '%s\t%s%s%s\0' "s:$name" "$TXT" "$name" "$R"                 # space row: name only, no dot
    tmux list-windows -t "$name" -F '#{window_index}	#{window_active}	#{window_name}' 2>/dev/null \
    | while IFS=$'\t' read -r widx wact wname; do
        tst=$(printf '%s\n' "$agents" | awk -F'\t' -v pre="$name:$widx." '
          index($2,pre)==1 { r["read"]=0;r["unread"]=1;r["working"]=2;r["waiting"]=3;
                             if(r[$1]>=b){b=r[$1];s=$1} } END{print s}')   # best status of any agent in this tab
        case "$tst" in
          working) tdot="${GOLD}●${R}" ;; waiting) tdot="${LOVE}●${R}" ;;
          unread)  tdot="${FOAM}●${R}" ;; read)    tdot="${MUTE}●${R}" ;;
          *)       tdot="${MUTE}·${R}" ;;                                # no agent in this tab → centered middot
        esac
        disp="  ${tdot} ${MUTE}${wname}${R}"; vis=$(( 4 + ${#wname} ))
        [ "${att:-0}" -ge 1 ] && [ "$wact" = 1 ] && disp=$(_hl "$disp" "$vis")   # attached space's active tab → gray bg
        printf '%s\t%s\0' "w:$name:$widx" "$disp"
      done
  done
  printf '%s\t%s\0' '-' ''                                               # blank spacer above the divider
  printf '%s\t%s\0' '-' "${MUTE}agents${R}"                              # section divider (no-op on click)
  printf '%s\n' "$agents" | while IFS=$'\t' read -r st target window pane_id; do
    [ -n "$target" ] || continue
    case "$st" in
      working) acolor=$GOLD ;; waiting) acolor=$LOVE ;; unread) acolor=$FOAM ;; *) acolor=$MUTE ;;
    esac
    sess=${target%%:*}
    disp="${acolor}●${R} ${TXT}${sess}${R} ${MUTE}· ${window}${R}"; vis=$(( 5 + ${#sess} + ${#window} ))
    [ -n "$foctarget" ] && [ "$target" = "$foctarget" ] && disp=$(_hl "$disp" "$vis")   # focused agent → gray bg
    printf '%s\t%s\0' "a:$target" "$disp"
  done
}

# panel: the live, clickable sidebar UI — runs inside the sidebar pane. A "spaces" header over the
# space/tab tree, an "agents" divider over the agent list. A single left-click (or enter) switches
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
      --header='spaces ' --header-first --delimiter='\t' --with-nth=2 \
      --color='bg+:-1,fg+:-1,gutter:-1,header:#6e6a86,pointer:-1' \
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

# refresh: push a flash-free reload into every open sidebar — but only when the panel's rendered content
# actually changed. We dedup on a cksum of __lines (identical across sidebars, since the list is now
# pane-independent): a stored sig equal to the current one means nothing visible changed, so we skip the
# POST entirely. reload-sync swaps the list atomically (no clear-then-repaint flicker). Wired to the
# structural hooks (immediate) and, via _refresh_agents, pane-title-changed. No-op when no sidebar has a
# live socket, or curl/fzf --listen is unavailable.
_refresh() {
  command -v curl >/dev/null 2>&1 || return 0
  local socks sig sigf sock; socks=$(_live_socks); [ -n "$socks" ] || return 0
  sig=$(__lines | cksum); sigf="/tmp/agent-sidebar-sig-${UID:-0}"
  [ "$sig" = "$(cat "$sigf" 2>/dev/null)" ] && return 0                 # nothing visible changed → no reload
  printf '%s' "$sig" > "$sigf"
  printf '%s\n' "$socks" | while IFS= read -r sock; do
    curl -s --unix-socket "$sock" "http://localhost/" --data-binary "reload-sync('$0' __lines)" >/dev/null 2>&1 || true
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

# mark-read: you switched into a pane — if it's an agent showing "unread" (blue), flip it to "read" (gray),
# then refresh so its dot and the follow-focus gray highlight update. Wired to pane-focus-in. Only touches
# unread (leaves working/waiting), and refreshes regardless so the highlight tracks focus into any pane.
_mark_read() {
  local fp pid f
  fp=$(_focused_pane); pid=${fp%%$'\t'*}
  if [ -n "$pid" ]; then
    f=$(_statef "$pid")
    [ "$(cat "$f" 2>/dev/null || true)" = unread ] && printf 'read' > "$f"
  fi
  _refresh
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
  refresh)      _refresh ;;           # internal: invoked by the structural tmux hooks (live sidebar reload)
  refresh-agents) _refresh_agents ;;  # internal: invoked by the pane-title-changed hook (debounced agent-state reload)
  mark-read)    _mark_read ;;         # internal: invoked by the pane-focus-in hook (unread → read + follow focus)
  fix-width)    _fix_width ;;         # internal: invoked by the client-resized hook (pin sidebar width)
  reap)         _reap "${2:-}" ;;     # internal: invoked by the window-layout-changed hook
  *) echo "tmux-agents: unknown mode '${1}' (expected: pick|count|sidebar)" >&2; exit 1 ;;
esac
