#!/usr/bin/env bash
# Lazygit sidebar: a fixed-width, full-height lazygit pane on the far left of the window (prefix g toggles).
# Same pop-open mechanics as the retired agent sidebar (archive/agent-sidebar/): -f -h -b split, tagged
# @sidebar=1 (generic fixed-width-left-sidebar pane tag) so tmux-even-columns.sh keeps its width, automatic-rename keeps the window name, and the
# real-pane counts (dotslg/metalg/activelg) skip it; width re-pinned on resize/layout change; closing hands
# its width back proportionally. Unlike the agent sidebar it is a normal, focusable pane — opening it
# focuses it and nothing deflects focus away (no mark-read deflect), since you work in it.
#
# Modes:
#   toggle <path>   open (focused, lazygit in <path>'s repo) or close this window's sidebar
#   close <pane>    reclaim + kill <pane>; run by the pane itself when lazygit quits
#   layout <win>    window-layout-changed hook: reap a window left with only the sidebar, then fix-width
#   fix-width       window-resized hook: snap every sidebar back to SIDEBAR_COLS
set -uo pipefail

SIDEBAR_COLS=50

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
# proportionally to fill the width the sidebar vacated, so closing is width-neutral (even columns stay even,
# no ratchet onto the neighbour). Prints "csum,body", or returns 1 on shapes it won't touch (top level not a
# left/right split, a column with a nested left/right split, sidebar not found, <2 real columns) — the caller
# then plain-kills and lets tmux redistribute. Copied from the archived agent sidebar.
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

# _close: kill sidebar pane $1, then apply the width-neutral layout. Both commands go in ONE tmux invocation
# so it still completes when the caller is the sidebar pane itself (killing it kills this script).
_close() {
  local pane=$1 win layout newl
  read -r win layout < <(tmux display-message -p -t "$pane" '#{window_id} #{window_layout}' 2>/dev/null) || return 0
  newl=$(_reclaim_layout "$layout" "${pane#%}") || newl=""
  if [ -n "$newl" ]; then
    tmux kill-pane -t "$pane" \; select-layout -t "$win" "$newl" 2>/dev/null || tmux kill-pane -t "$pane" 2>/dev/null
  else
    tmux kill-pane -t "$pane" 2>/dev/null
  fi
  return 0
}

# _open: full-height left split running lazygit in <path>'s repo. `lg` (60-functions.zsh) picks the right
# GH token per remote host; a non-repo <path> falls back to its most recently visited nested repo (like kk
# used to). When lazygit quits, the pane closes itself through `close` so the width is reclaimed.
# `exec zsh -il -c`, not plain `sh -c '...; ...'`: tmux's sh won't hand lazygit the foreground tty when a
# command follows it (it dies instantly) — same reason as _kk_stay in mux-tmux.zsh.
_open() {
  local dir=${1:-$HOME} pane inner
  inner='git rev-parse --git-dir >/dev/null 2>&1 || { r=$(_recent_nested_repo); [[ -n $r ]] && { _suppress_chpwd=1; builtin cd -- $r; _suppress_chpwd=0; }; }; lg; exec '"$(printf '%q' "$0")"' close "$TMUX_PANE"'
  pane=$(tmux split-window -f -h -b -l "$SIDEBAR_COLS" -c "$dir" -P -F '#{pane_id}' \
    "exec zsh -il -c $(printf '%q' "$inner")") || return 0
  [ -n "$pane" ] && tmux set-option -p -t "$pane" @sidebar 1 2>/dev/null
  return 0
}

_toggle() {
  local existing
  existing=$(tmux list-panes -F '#{pane_id} #{@sidebar}' | awk '$2 == "1" { print $1; exit }')
  if [ -n "$existing" ]; then _close "$existing"; else _open "${1:-}"; fi
}

# _fix_width: snap every sidebar back to SIDEBAR_COLS. Runs on window-layout-changed, which its own
# resize-pane re-fires, so: only resize a sidebar whose width differs (ends the chain), and coalesce bursts
# behind a mkdir lock + short debounce so two passes never overlap. Same scheme as the agent sidebar.
_fix_width() {
  local lock="/tmp/lazygit-sidebar-fixwidth-${UID:-0}.lock"
  mkdir "$lock" 2>/dev/null || return 0
  (
    trap 'rmdir "$lock" 2>/dev/null' EXIT
    sleep 0.2
    tmux list-panes -a -F '#{@sidebar}	#{pane_id}	#{pane_width}' 2>/dev/null \
    | awk -F'\t' -v w="$SIDEBAR_COLS" '$1==1 && $3+0 != w+0 {print $2}' \
    | while IFS= read -r pid; do tmux resize-pane -t "$pid" -x "$SIDEBAR_COLS" 2>/dev/null || true; done
  ) &
}

# _reap: close window $1 when the sidebar is its SOLE surviving pane, so exiting your last real pane closes
# the tab instead of leaving a lone sidebar. One list-panes, kill iff ≥1 pane, ≥1 sidebar, 0 real panes —
# never kills a window that still holds a real pane.
_reap() {
  local win="${1:-}"
  [ -n "$win" ] || return 0
  tmux list-panes -t "$win" -F '#{@sidebar}' 2>/dev/null | awk '
    { n++; if ($0 == "1") sb++; else real++ }
    END { exit (n > 0 && sb > 0 && real == 0) ? 0 : 1 }' \
    && tmux kill-window -t "$win" 2>/dev/null || true
}

case "${1:-}" in
  toggle)    _toggle "${2:-}" ;;
  close)     [ -n "${2:-}" ] && _close "$2" ;;
  layout)    _reap "${2:-}"; _fix_width ;;
  fix-width) _fix_width ;;
  __reclaim) _reclaim_layout "${2:-}" "${3:-}" ;;   # test hook: pure layout rewrite, no tmux
  *) echo "usage: $0 toggle <path> | close <pane> | layout <win> | fix-width" >&2; exit 2 ;;
esac
