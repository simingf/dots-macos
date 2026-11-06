#!/usr/bin/env bash
# tmux-lazygit.sh — lazygit sidebar (prefix g): fixed-width, full-height, focused pane on the window's left.
# Tagged @sidebar=1, so even-columns keeps its width, automatic-rename ignores it, and pane counts skip it.
#
# Repo (_resolve, first hit wins): an nvim pane's @nvim_repo in this window (lua/config/tmux_lazygit.lua),
# the active pane's repo, the top-zoxide repo ≤3 levels below (else newest .git), else a notification.
# `follow` (called by nvim) swaps in the lazygit for nvim's repo while open, or pre-warms one while closed.
#
# Parking: closing break-panes lazygit into the hidden `_lazygit` session (one per repo, newest STASH_MAX
# kept) and opening joins it back (~tens of ms, state kept). Quitting lazygit (q) really closes the pane.
#
# Modes:
#   toggle <path> <pane>  open (focused) on the resolved repo, or park this window's sidebar
#   follow <nvim-pane>    swap the sidebar in <nvim-pane>'s window to its @nvim_repo, or pre-warm it if none open
#   edit <file> [line]    lazygit's edit (`k`) (os.edit via scripts/lazygit-tmux-edit.yml): open in this window's nvim
#   close <pane>          reclaim + kill <pane>; run by the pane itself when lazygit quits
#   layout <win>    window-layout-changed hook: park a window's sidebar if it's the sole pane, then fix-width
#   fix-width       window-resized hook: snap every sidebar back to its window's _width
#   gc              session-closed hook: kill the stash when it's the only session left
set -uo pipefail

SIDEBAR_PCT=25     # % of window width, min SIDEBAR_MIN columns
SIDEBAR_MIN=75
STASH=_lazygit
STASH_MAX=5

# _width <window-width> → sidebar columns
_width() {
  local w=$(($1 * SIDEBAR_PCT / 100))
  echo $((w < SIDEBAR_MIN ? SIDEBAR_MIN : w))
}

# tmux layout_checksum (layout-custom.c) over a layout body (no "csum,"); same as tmux-even-columns.sh.
_csum() {
  local s=$1 c=0 i ch
  for ((i = 0; i < ${#s}; i++)); do
    printf -v ch '%d' "'${s:i:1}"
    c=$(((c >> 1) + ((c & 1) << 15)))
    c=$(((c + ch) & 0xffff))
  done
  printf '%04x' "$c"
}

# _reclaim_layout <layout> <sidebar-num>: the layout after removing the sidebar column, the other columns
# scaled proportionally into its width (so closing doesn't all go to the neighbour). Prints "csum,body";
# returns 1 on shapes it won't touch, and the caller lets tmux redistribute.
_reclaim_layout() {
  local layout=$1 sidebar_id=$2 body root W inner
  body=${layout#*,}                                # strip "csum,"
  case $body in *,0,0\{*\}) ;; *) return 1 ;; esac  # top level must be a left/right split "WxH,0,0{...}"
  root=${body%%\{*}; W=${root%%x*}
  inner=${body#*\{}; inner=${inner%\}}
  # split into column cells — same parse as tmux-even-columns.sh
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
  # widths + sidebar flag; reject a nested left/right split
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
  # proportional floors, rounding leftover handed out left to right
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
  # rebuild without the sidebar, re-chaining X from 0
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

# The stash session; a `sleep` window keeps it alive while empty.
_stash_ensure() {
  tmux has-session -t "=$STASH" 2>/dev/null ||
    tmux new-session -d -s "$STASH" -n hold 'exec sleep 2147483647' 2>/dev/null
}

# _stashed <repo> → parked pane id, if any
_stashed() {
  tmux list-panes -s -t "=$STASH" -F '#{@sidebar_repo}	#{pane_id}' 2>/dev/null |
    awk -F'\t' -v r="$1" '$1 == r { print $2; exit }'
}

# _park_prep <pane>: kill any other parked lazygit on the same repo (one per repo)
_park_prep() {
  local repo old
  _stash_ensure
  repo=$(tmux display-message -p -t "$1" '#{@sidebar_repo}' 2>/dev/null)
  [ -n "$repo" ] || return 0
  old=$(_stashed "$repo")
  [[ -n $old && $old != "$1" ]] && tmux kill-pane -t "$old" 2>/dev/null
  return 0
}

# _parked <pane>: stamp it, then evict the oldest beyond STASH_MAX
_parked() {
  tmux set-option -p -t "$1" @stashed_at "$(date +%s)" 2>/dev/null
  tmux list-panes -s -t "=$STASH" -F '#{@sidebar}	#{@stashed_at}	#{pane_id}' 2>/dev/null |
    awk -F'\t' '$1 == "1"' | sort -t$'\t' -k2,2n |
    awk -F'\t' -v max="$STASH_MAX" '{ id[NR] = $3 } END { for (i = 1; i <= NR - max; i++) print id[i] }' |
    while IFS= read -r p; do tmux kill-pane -t "$p" 2>/dev/null; done
  return 0
}

# _close <pane> [park]: park or kill the sidebar, then apply the reclaimed layout — in ONE tmux call, since
# killing the pane may kill this script (`close` runs inside it).
_close() {
  local pane=$1 win layout newl
  local -a rm=(kill-pane -t "$pane")
  if [ "${2:-}" = park ]; then _park_prep "$pane"; rm=(break-pane -d -s "$pane" -t "=$STASH:"); fi
  read -r win layout < <(tmux display-message -p -t "$pane" '#{window_id} #{window_layout}' 2>/dev/null) || return 0
  # tmux ≥3.8 reports JSON → classic (floating panes → plain remove)
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

# _nested_repo <dir>: repo ≤3 levels below with the top zoxide score (a visit inside a repo counts for
# it), else the newest .git, else nothing.
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

# _resolve <path> <pane>: the repo to show (see header)
_resolve() {
  local dir=${1:-$HOME} pane=${2:-} r
  r=$( { tmux display-message -p -t "$pane" '#{@nvim_repo}'; tmux list-panes -t "$pane" -F '#{@nvim_repo}'; } 2>/dev/null \
       | awk 'NF { print; exit }')
  [[ -n $r && -d $r ]] && { printf '%s\n' "$r"; return; }
  r=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [[ -n $r ]] && { printf '%s\n' "$r"; return; }
  _nested_repo "$dir"
}

# _cmd: the pane command. `lg` (60-functions.zsh) sets the per-host GH token; `close` on quit reclaims the
# width. zsh -f skips rc files (~150ms); -i keeps job control so pane_current_command = lazygit (runall skips it).
_cmd() {
  local inner fns
  fns="$(cd "$(dirname "$0")/.." && pwd)/.config/zsh/60-functions.zsh"
  inner='source '"$(printf '%q' "$fns")"'; lg; exec '"$(printf '%q' "$0")"' close "$TMUX_PANE"'
  printf 'exec zsh -fic %q' "$inner"
}

# _spawn <repo>: cold-start a lazygit in the stash; prints its pane id
_spawn() {
  local p
  _stash_ensure
  p=$(tmux new-window -d -t "=$STASH:" -c "$1" -P -F '#{pane_id}' "$(_cmd)") || return 1
  _tag "$p" "$1"
  printf '%s\n' "$p"
}

# _tag <pane> <repo>
_tag() {
  tmux set-option -p -t "$1" @sidebar 1 \; set-option -p -t "$1" @sidebar_repo "$2" 2>/dev/null
}

# _open <path> <pane>: join the parked lazygit for the repo, else split a new one
_open() {
  local repo sb cols
  repo=$(_resolve "$@")
  if [[ -z $repo ]]; then
    "$(dirname "$0")/tmux-notify.sh" "no git repo here"
    return 0
  fi
  cols=$(_width "$(tmux display-message -p -t "$2" '#{window_width}')")
  sb=$(_stashed "$repo")
  [ -n "$sb" ] && tmux join-pane -f -h -b -l "$cols" -s "$sb" -t "$2" 2>/dev/null && return 0
  sb=$(tmux split-window -f -h -b -l "$cols" -t "$2" -c "$repo" -P -F '#{pane_id}' "$(_cmd)") || return 0
  [ -n "$sb" ] && _tag "$sb" "$repo"
  return 0
}

_toggle() {
  local existing pane=$2
  existing=$(tmux list-panes -t "$pane" -F '#{pane_id} #{@sidebar}' | awk '$2 == "1" { print $1; exit }')
  if [ -n "$existing" ]; then _close "$existing" park; else _open "$@"; fi
}

# _follow <nvim-pane>: open sidebar on another repo → swap in @nvim_repo's lazygit (swap-pane -d keeps
# cell, width, focus) and park the old one. No sidebar → pre-warm (or re-stamp) a parked one.
_follow() {
  local np=$1 repo row sb cur new
  repo=$(tmux display-message -p -t "$np" '#{@nvim_repo}' 2>/dev/null)
  [[ -n $repo && -d $repo ]] || return 0
  row=$(tmux list-panes -t "$np" -F '#{@sidebar}	#{pane_id}	#{@sidebar_repo}' 2>/dev/null | awk -F'\t' '$1 == "1" { print $2, ($3 == "" ? "-" : $3); exit }')
  new=$(_stashed "$repo")
  if [ -z "$row" ]; then
    [ -n "$new" ] || new=$(_spawn "$repo") || return 0
    _parked "$new"
    return 0
  fi
  read -r sb cur <<<"$row"                          # placeholder keeps an empty repo from collapsing
  [[ $cur == "$repo" ]] && return 0
  _park_prep "$sb"
  [ -n "$new" ] || new=$(_spawn "$repo") || return 0
  tmux swap-pane -d -s "$new" -t "$sb" 2>/dev/null && _parked "$sb"
  return 0
}

# _edit <file> [line]: lazygit's edit (`k`, via lazygit-tmux-edit.yml) → open in an nvim pane of
# $TMUX_PANE's window (by @nvim_server; prefer <file>'s repo, then the last-active pane) and focus it.
# No reachable nvim → a new full-height nvim pane on the right edge.
_edit() {
  local file=$1 line=${2:-0} repo np="" srv="" q="'"
  [[ $file == /* ]] || file=$PWD/$file
  [[ $line =~ ^[0-9]+$ ]] || line=0
  repo=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)
  IFS=$'\t' read -r np srv < <(tmux list-panes -t "${TMUX_PANE:-}" -F '#{pane_id}	#{@nvim_server}	#{@nvim_repo}	#{pane_last}' 2>/dev/null |
    awk -F'\t' -v r="$repo" '$2 != "" { s = ($3 == r) * 2 + $4; if (!n++ || s > best) { best = s; out = $1 "\t" $2 } } END { if (n) print out }')
  if [[ -n $np ]] && nvim --server "$srv" --remote-expr "v:lua.TmuxLazygitEdit('${file//$q/$q$q}', $line)" >/dev/null 2>&1; then
    tmux select-pane -t "$np"
    return 0
  fi
  local -a cmd=(nvim -- "$file"); ((line > 0)) && cmd=(nvim "+$line" -- "$file")
  tmux split-window -h -f -t "${TMUX_PANE:-}" -c "${repo:-$(dirname "$file")}" "${cmd[@]}"
}

# _fix_width: snap every sidebar to its _width. Its resize re-fires window-layout-changed, so only resize
# on a mismatch (ends the loop) and coalesce bursts behind a mkdir lock + debounce.
_fix_width() {
  local lock="/tmp/lazygit-sidebar-fixwidth-${UID:-0}.lock"
  mkdir "$lock" 2>/dev/null || return 0
  (
    trap 'rmdir "$lock" 2>/dev/null' EXIT
    sleep 0.2
    tmux list-panes -a -F '#{@sidebar}	#{pane_id}	#{pane_width}	#{session_name}	#{window_width}' 2>/dev/null \
    | while IFS=$'\t' read -r tag pid pw sess ww; do
        [[ $tag == 1 && $sess != "$STASH" ]] || continue
        w=$(_width "$ww")
        [[ $pw != "$w" ]] && tmux resize-pane -t "$pid" -x "$w" 2>/dev/null
      done
  ) &
}

# _reap <win>: if the sidebar is the window's only pane, park it (which closes the window).
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

# _gc: kill the stash once it's the only session left (else it keeps the server alive)
_gc() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -qvx "$STASH" ||
    tmux kill-session -t "=$STASH" 2>/dev/null
  return 0
}

case "${1:-}" in
  toggle)    _toggle "${2:-}" "${3:-}" ;;
  follow)    [ -n "${2:-}" ] && _follow "$2" ;;
  edit)      [ -n "${2:-}" ] && _edit "$2" "${3:-}" ;;
  close)     [ -n "${2:-}" ] && _close "$2" ;;
  layout)    _reap "${2:-}"; _fix_width ;;
  fix-width) _fix_width ;;
  gc)        _gc ;;
  __reclaim) _reclaim_layout "${2:-}" "${3:-}" ;;   # test hook: pure layout rewrite, no tmux
  *) echo "usage: $0 toggle <path> <pane> | follow <nvim-pane> | edit <file> [line] | close <pane> | layout <win> | fix-width | gc" >&2; exit 2 ;;
esac
