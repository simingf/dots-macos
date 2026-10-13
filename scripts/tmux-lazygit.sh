#!/usr/bin/env bash
# Lazygit sidebar: a fixed-width, full-height lazygit pane on the far left of the window (prefix g toggles).
# Same pop-open mechanics as the retired agent sidebar (archive/agent-sidebar/): -f -h -b split, tagged
# @sidebar=1 (generic fixed-width-left-sidebar pane tag) so tmux-even-columns.sh keeps its width, automatic-rename keeps the window name, and the
# real-pane counts (dotslg/metalg/activelg) skip it; width re-pinned on resize/layout change; closing hands
# its width back proportionally. Unlike the agent sidebar it is a normal, focusable pane — opening it
# focuses it and nothing deflects focus away (no mark-read deflect), since you work in it.
#
# Which repo (_resolve, first hit wins): the repo an nvim pane in this window is looking at (@nvim_repo,
# published by nvim's lua/config/tmux_lazygit.lua — the active pane's first); else the repo containing the
# active pane's dir; else, among repos ≤3 levels below it, the highest zoxide score (newest .git mtime if
# none of them are in zoxide); else nothing opens and a "no git repo here" notification shows instead.
# While open, the sidebar follows nvim: when nvim's repo changes, `follow` swaps in that repo's lazygit.
#
# Instant toggle: closing never kills lazygit, it parks the pane (break-pane) in the hidden STASH session,
# one per repo, and opening/following joins/swaps a parked one back in (~tens of ms, state kept) — only a
# repo with nothing parked cold-starts lazygit. The STASH_MAX most recently parked are kept; `gc` (on
# session-closed) kills the stash once no real session is left, so it never keeps the server alive alone.
# Sessions named `_*` are hidden from the session pickers (tmux-fzf-sessions.sh, tl/ta/tk, pane-content).
# Quitting lazygit (q) still really closes the pane.
#
# Modes:
#   toggle <path> <pane>  open (focused) on the resolved repo, or park this window's sidebar
#   follow <nvim-pane>    swap the sidebar in <nvim-pane>'s window to its @nvim_repo (no-op if none open)
#   close <pane>          reclaim + kill <pane>; run by the pane itself when lazygit quits
#   layout <win>    window-layout-changed hook: park a window's sidebar if it's the sole pane, then fix-width
#   fix-width       window-resized hook: snap every sidebar back to SIDEBAR_COLS
#   gc              session-closed hook: kill the stash when it's the only session left
set -uo pipefail

SIDEBAR_COLS=50
STASH=_lazygit
STASH_MAX=5

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

# _stash_ensure: create the hidden stash session (a `sleep` placeholder window keeps it alive while empty).
_stash_ensure() {
  tmux has-session -t "=$STASH" 2>/dev/null ||
    tmux new-session -d -s "$STASH" -n hold 'exec sleep 2147483647' 2>/dev/null
}

# _stashed <repo>: the parked sidebar pane for <repo>, if any.
_stashed() {
  tmux list-panes -s -t "=$STASH" -F '#{@sidebar_repo}	#{pane_id}' 2>/dev/null |
    awk -F'\t' -v r="$1" '$1 == r { print $2; exit }'
}

# _park_prep <pane>: make room for parking <pane> — kill any parked lazygit on the same repo (one per repo).
_park_prep() {
  local repo old
  _stash_ensure
  repo=$(tmux display-message -p -t "$1" '#{@sidebar_repo}' 2>/dev/null)
  [ -n "$repo" ] || return 0
  old=$(_stashed "$repo")
  [[ -n $old && $old != "$1" ]] && tmux kill-pane -t "$old" 2>/dev/null
  return 0
}

# _parked <pane>: stamp a just-parked pane, then evict the oldest-parked beyond STASH_MAX.
_parked() {
  tmux set-option -p -t "$1" @stashed_at "$(date +%s)" 2>/dev/null
  tmux list-panes -s -t "=$STASH" -F '#{@sidebar}	#{@stashed_at}	#{pane_id}' 2>/dev/null |
    awk -F'\t' '$1 == "1"' | sort -t$'\t' -k2,2n |
    awk -F'\t' -v max="$STASH_MAX" '{ id[NR] = $3 } END { for (i = 1; i <= NR - max; i++) print id[i] }' |
    while IFS= read -r p; do tmux kill-pane -t "$p" 2>/dev/null; done
  return 0
}

# _close <pane> [park]: remove sidebar pane $1 — park it in the stash (`park`) or kill it — then apply the
# width-neutral layout. Both commands go in ONE tmux invocation so it still completes when the caller is the
# sidebar pane itself (killing it kills this script). Any other $2 (a pre-stash pane's gen) means kill.
_close() {
  local pane=$1 win layout newl
  local -a rm=(kill-pane -t "$pane")
  if [ "${2:-}" = park ]; then _park_prep "$pane"; rm=(break-pane -d -s "$pane" -t "=$STASH:"); fi
  read -r win layout < <(tmux display-message -p -t "$pane" '#{window_id} #{window_layout}' 2>/dev/null) || return 0
  # tmux ≥3.8 reports JSON — convert to classic first (floating panes → unsupported → plain remove)
  layout=$("$(dirname "$0")/tmux-layout-classic.sh" "$layout") || layout=""
  newl=$(_reclaim_layout "$layout" "${pane#%}") || newl=""
  if [ -n "$newl" ]; then
    tmux "${rm[@]}" \; select-layout -t "$win" "$newl" 2>/dev/null || tmux "${rm[@]}" 2>/dev/null
  else
    tmux "${rm[@]}" 2>/dev/null
  fi
  [ "${2:-}" = park ] && _parked "$pane"
  return 0
}

# _nested_repo <dir>: among git repos ≤3 levels below <dir>, the one with the highest zoxide score — zoxide
# lists highest-first, and a visit anywhere inside a repo counts for that repo (climb to its .git, but not
# above <dir>). If none are in zoxide yet, the one whose .git changed most recently. Prints nothing if none.
_nested_repo() {
  local base=${1%/} d r rel
  if command -v zoxide >/dev/null; then
    while IFS= read -r d; do
      [[ $d == "$base"/* ]] || continue
      r=$d
      while [[ $r != "$base" && ! -e $r/.git ]]; do r=${r%/*}; done
      [[ $r == "$base" ]] && continue
      rel=${r#"$base"/}; rel=${rel//[^\/]/}          # one / per extra level
      ((${#rel} <= 2)) && { printf '%s\n' "$r"; return; }
    done < <(zoxide query --list 2>/dev/null)
  fi
  local -a gits=()
  shopt -s nullglob; gits=("$base"/*/.git "$base"/*/*/.git "$base"/*/*/*/.git); shopt -u nullglob
  ((${#gits[@]})) && { r=$(ls -1td -- "${gits[@]}" | head -1); printf '%s\n' "${r%/.git}"; }
}

# _resolve <path> <pane>: the repo to show (see header), or nothing.
_resolve() {
  local dir=${1:-$HOME} pane=${2:-} r
  r=$( { tmux display-message -p -t "$pane" '#{@nvim_repo}'; tmux list-panes -t "$pane" -F '#{@nvim_repo}'; } 2>/dev/null \
       | awk 'NF { print; exit }')
  [[ -n $r && -d $r ]] && { printf '%s\n' "$r"; return; }
  r=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [[ -n $r ]] && { printf '%s\n' "$r"; return; }
  _nested_repo "$dir"
}

# _cmd: the sidebar pane command. `lg` (60-functions.zsh) picks the right GH token per remote host.
# When lazygit quits, the pane closes itself through `close` so the width is reclaimed. `exec zsh -il -c`,
# not plain `sh -c '...; ...'`: tmux's sh won't hand lazygit the foreground tty when a command follows it
# (it dies instantly) — same reason as _kk_stay in mux-tmux.zsh.
_cmd() {
  local inner
  inner='lg; exec '"$(printf '%q' "$0")"' close "$TMUX_PANE"'
  printf 'exec zsh -il -c %q' "$inner"
}

# _tag <pane> <repo>
_tag() {
  tmux set-option -p -t "$1" @sidebar 1 \; set-option -p -t "$1" @sidebar_repo "$2" 2>/dev/null
}

# _open <path> <pane>: full-height left column on the resolved repo, focused — the parked lazygit if there
# is one, else a fresh split.
_open() {
  local repo sb
  repo=$(_resolve "$@")
  if [[ -z $repo ]]; then
    "$(dirname "$0")/tmux-notify.sh" "no git repo here"
    return 0
  fi
  sb=$(_stashed "$repo")
  [ -n "$sb" ] && tmux join-pane -f -h -b -l "$SIDEBAR_COLS" -s "$sb" -t "$2" 2>/dev/null && return 0
  sb=$(tmux split-window -f -h -b -l "$SIDEBAR_COLS" -c "$repo" -P -F '#{pane_id}' "$(_cmd)") || return 0
  [ -n "$sb" ] && _tag "$sb" "$repo"
  return 0
}

_toggle() {
  local existing pane=${2:-}
  # no pane arg (a server still running a pre-reload `bind g`): fall back to the current client's pane
  [ -n "$pane" ] || pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
  set -- "${1:-}" "$pane"
  existing=$(tmux list-panes -t "$pane" -F '#{pane_id} #{@sidebar}' | awk '$2 == "1" { print $1; exit }')
  if [ -n "$existing" ]; then _close "$existing" park; else _open "$@"; fi
}

# _follow <nvim-pane>: if that window has a sidebar on a different repo than the pane's @nvim_repo, swap in
# that repo's lazygit (parked, else cold-started in the stash) and park the old one. swap-pane keeps the
# cell, its width, and (-d) focus where it is.
_follow() {
  local np=$1 repo row sb cur new
  repo=$(tmux display-message -p -t "$np" '#{@nvim_repo}' 2>/dev/null)
  [[ -n $repo && -d $repo ]] || return 0
  row=$(tmux list-panes -t "$np" -F '#{@sidebar}	#{pane_id}	#{@sidebar_repo}' 2>/dev/null | awk -F'\t' '$1 == "1" { print $2, ($3 == "" ? "-" : $3); exit }')
  [ -n "$row" ] || return 0
  read -r sb cur <<<"$row"                          # placeholder keeps an empty repo from collapsing
  [[ $cur == "$repo" ]] && return 0
  _park_prep "$sb"
  new=$(_stashed "$repo")
  if [ -z "$new" ]; then
    new=$(tmux new-window -d -t "=$STASH:" -c "$repo" -P -F '#{pane_id}' "$(_cmd)") || return 0
    _tag "$new" "$repo"
  fi
  tmux swap-pane -d -s "$new" -t "$sb" 2>/dev/null && _parked "$sb"
  return 0
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
    tmux list-panes -a -F '#{@sidebar}	#{pane_id}	#{pane_width}	#{session_name}' 2>/dev/null \
    | awk -F'\t' -v w="$SIDEBAR_COLS" -v st="$STASH" '$1==1 && $3+0 != w+0 && $4 != st {print $2}' \
    | while IFS= read -r pid; do tmux resize-pane -t "$pid" -x "$SIDEBAR_COLS" 2>/dev/null || true; done
  ) &
}

# _reap: close window $1 when the sidebar is its SOLE surviving pane, so exiting your last real pane closes
# the tab instead of leaving a lone sidebar — by parking the sidebar (moving it out closes the window). Acts
# iff exactly 1 pane and it's a sidebar outside the stash — never touches a window holding a real pane.
_reap() {
  local win="${1:-}" pane
  [ -n "$win" ] || return 0
  pane=$(tmux list-panes -t "$win" -F '#{session_name}	#{@sidebar}	#{pane_id}' 2>/dev/null | awk -F'\t' -v st="$STASH" '
    { n++; if ($1 != st && $2 == "1") p = $3 }
    END { if (n == 1 && p != "") print p }')
  [ -n "$pane" ] || return 0
  _park_prep "$pane"
  tmux break-pane -d -s "$pane" -t "=$STASH:" 2>/dev/null && _parked "$pane"
  return 0
}

# _gc: kill the stash once it's the only session left, so parked lazygits never keep the server alive alone.
_gc() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -qvx "$STASH" ||
    tmux kill-session -t "=$STASH" 2>/dev/null
  return 0
}

case "${1:-}" in
  toggle)    _toggle "${2:-}" "${3:-}" ;;
  follow)    [ -n "${2:-}" ] && _follow "$2" ;;
  close)     [ -n "${2:-}" ] && _close "$2" "${3:-}" ;;   # $3: a pre-stash pane's gen → plain kill
  layout)    _reap "${2:-}"; _fix_width ;;
  fix-width) _fix_width ;;
  gc)        _gc ;;
  __reclaim) _reclaim_layout "${2:-}" "${3:-}" ;;   # test hook: pure layout rewrite, no tmux
  *) echo "usage: $0 toggle <path> <pane> | follow <nvim-pane> | close <pane> | layout <win> | fix-width | gc" >&2; exit 2 ;;
esac
