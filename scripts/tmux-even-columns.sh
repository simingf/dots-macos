#!/usr/bin/env bash
# tmux-even-columns.sh — `prefix 0`: equalize the widths of the current window's
# top-level columns, with two differences from `select-layout even-horizontal`:
#   1. the agent sidebar keeps its current width (it's not made an equal column).
#   2. vertically stacked panes stay stacked — a column split top/bottom keeps its
#      stack instead of being flattened into separate full-height equal columns.
#
# It rewrites the tmux layout string directly: split the top-level {..} (left/right)
# group into columns, keep the sidebar column's width, split the remaining width
# evenly across the other columns, re-chain the X offsets, and shift every cell
# inside each column (all cells in a vertical stack share the column's width + X, so
# a stack just moves/resizes as a unit — heights and Y are untouched).
#
# Falls back to `even-horizontal` for shapes it can't safely rewrite: a top level
# that isn't a left/right split (single pane, or an all-vertical stack → nothing to
# equalize, left as-is), or a column containing a nested left/right split (its inner
# widths would need proportional scaling — punt to tmux rather than risk a bad tile).
set -euo pipefail

win=$(tmux display-message -p '#{window_id}')
fallback() { tmux select-layout -t "$win" even-horizontal; exit 0; }

# tmux layout_checksum (layout-custom.c) over the body — excludes the leading "csum,".
csum() {
	local s=$1 c=0 i ch
	for ((i = 0; i < ${#s}; i++)); do
		printf -v ch '%d' "'${s:i:1}"
		c=$(((c >> 1) + ((c & 1) << 15)))
		c=$(((c + ch) & 0xffff))
	done
	printf '%04x' "$c"
}

layout=$(tmux display-message -p '#{window_layout}')
body=${layout#*,} # strip "csum,"

# top level must be "WxH,0,0{...}" (left/right split). A single pane or a top-level
# vertical stack ("...[...]") has nothing to equalize by width → leave as-is.
case $body in
*,0,0\{*\}) ;;
*) exit 0 ;;
esac

root=${body%%\{*}          # "WxH,0,0"
W=${root%%x*}              # window width
inner=${body#*\{}          # drop root + opening brace
inner=${inner%\}}          # drop closing brace

# sidebar pane's numeric id for THIS window (layout uses the number, not "%N"). Empty
# when the window has no sidebar — then every column is equalized (plain even widths).
sidebar_id=$(tmux list-panes -t "$win" -F '#{@agent_sidebar} #{pane_id}' 2>/dev/null |
	awk '$1==1 {print $2}' | head -1 | tr -d '%')

# Split the top-level group into column cells. First a depth-0 comma split into pieces,
# then regroup: every cell begins "WxH,X,Y" (WxH is the only token containing 'x'); a
# leaf adds ",id" (4 pieces), a group attaches "[...]"/"{...}" to the Y piece (3 pieces).
pieces=()
d=0 tok=""
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

# Regroup pieces into whole column cells.
cells=()
i=0
n=${#pieces[@]}
while ((i < n)); do
	whxy=${pieces[i]}     # WxH
	[[ $whxy == *x* ]] || fallback
	yp=${pieces[i + 2]}   # Y, possibly with an attached [..]/{..}
	if [[ $yp == *'['* || $yp == *'{'* ]]; then
		cells+=("${pieces[i]},${pieces[i + 1]},${pieces[i + 2]}") # group cell (3 pieces)
		i=$((i + 3))
	else
		cells+=("${pieces[i]},${pieces[i + 1]},${pieces[i + 2]},${pieces[i + 3]}") # leaf (4)
		i=$((i + 4))
	fi
done

ncols=${#cells[@]}
((ncols >= 2)) || exit 0 # nothing to equalize

# Per-column: width w0, x-offset x0, sidebar?, and reject nested left/right splits.
declare -a w0 x0 issb
sb_w=0 nonsb=0
for idx in "${!cells[@]}"; do
	c=${cells[idx]}
	[[ $c == *'{'* ]] && fallback  # nested horizontal split in a column → punt
	w0[idx]=${c%%x*}
	rest=${c#*,}
	x0[idx]=${rest%%,*}
	# sidebar iff this leaf's pane id equals sidebar_id (sidebar is always a leaf column)
	if [[ -n $sidebar_id && $c != *'['* ]]; then
		id=${c##*,}
		if [[ $id == "$sidebar_id" ]]; then
			issb[idx]=1; sb_w=${w0[idx]}; continue
		fi
	fi
	issb[idx]=0; nonsb=$((nonsb + 1))
done

((nonsb >= 1)) || exit 0 # only the sidebar → nothing to do

# Equal split of the width left after the sidebar and the (ncols-1) 1-col separators.
avail=$((W - (ncols - 1) - sb_w))
((avail >= nonsb)) || fallback # too narrow for a clean tile → let tmux handle minima
base=$((avail / nonsb))
rem=$((avail - base * nonsb)) # spread the remainder across the first `rem` non-sidebar cols

# Rewrite each column: keep the sidebar's width, give others base(+1), re-chain X.
newcols=()
cursor=0
for idx in "${!cells[@]}"; do
	c=${cells[idx]}
	if ((${issb[idx]} == 1)); then
		wn=$sb_w
	else
		wn=$base
		((rem > 0)) && { wn=$((base + 1)); rem=$((rem - 1)); }
	fi
	xn=$cursor
	# Every cell in this column shares w0/x0 (a vertical stack has one width + X, varying
	# only in height/Y). Remap "<w0>x<h>,<x0>," → "<wn>x<h>,<xn>," at each cell boundary.
	nc=$(sed -E "s/([,{[]|^)${w0[idx]}x([0-9]+),${x0[idx]},/\1${wn}x\2,${xn},/g" <<<"$c")
	newcols+=("$nc")
	cursor=$((xn + wn + 1))
done

# Reassemble, checksum, apply.
joined=$(
	IFS=,
	echo "${newcols[*]}"
)
new_body="${root}{${joined}}"
tmux select-layout -t "$win" "$(csum "$new_body"),${new_body}"
