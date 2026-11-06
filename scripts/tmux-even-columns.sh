#!/usr/bin/env bash
# tmux-even-columns.sh [pane <id> | border <x>] — equalize top-level column widths by rewriting the
# layout string. Unlike even-horizontal: the @sidebar column keeps its width and vertical stacks stay
# stacked (a stack moves/resizes as a unit).
#   (no args)       prefix 0. Top level not a left/right split → no-op; a column with a nested
#                   left/right split → even-horizontal.
#   pane <id>       after prefix M/I: that pane's column also keeps its width
#   border <x>      after a border drag: the column left of the border at x keeps its width
# Keep modes never fall back to even-horizontal (it would undo the resize).
set -euo pipefail

mode=${1:-} arg=${2:-}
win=$(tmux display-message -p '#{window_id}')
fallback() { [[ -n $mode ]] && exit 0; tmux select-layout -t "$win" even-horizontal; exit 0; }
keep_x=-1 # pane mode: x offset of the column to keep
[[ $mode == pane ]] && keep_x=$(tmux display-message -p -t "$arg" '#{pane_left}')

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

# tmux ≥3.8 reports JSON — convert to classic (floating panes → can't express → leave as-is)
layout=$("$(dirname "$0")/tmux-layout-classic.sh" "$(tmux display-message -p '#{window_layout}')") || exit 0
body=${layout#*,} # strip "csum,"

# top level must be "WxH,0,0{...}" (left/right split)
case $body in
*,0,0\{*\}) ;;
*) exit 0 ;;
esac

root=${body%%\{*}          # "WxH,0,0"
W=${root%%x*}              # window width
inner=${body#*\{}          # drop root + opening brace
inner=${inner%\}}          # drop closing brace

# @sidebar pane's number (layout drops the "%"), or empty
sidebar_id=$(tmux list-panes -t "$win" -F '#{@sidebar} #{pane_id}' 2>/dev/null |
	awk '$1==1 {print $2}' | head -1 | tr -d '%')

# Depth-0 comma split, then regroup into cells: each starts "WxH,X,Y"; a leaf adds ",id" (4 pieces),
# a group has "[..]"/"{..}" attached to Y (3 pieces).
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
sb_w=0 nonsb=0 keep_idx=-1
for idx in "${!cells[@]}"; do
	c=${cells[idx]}
	[[ $c == *'{'* ]] && fallback  # nested horizontal split in a column → punt
	w0[idx]=${c%%x*}
	rest=${c#*,}
	x0[idx]=${rest%%,*}
	# keep target: the column at keep_x, or whose right edge is within 1 of the border
	if [[ $mode == pane ]] && ((x0[idx] == keep_x)); then keep_idx=$idx; fi
	if [[ $mode == border ]]; then
		dist=$((arg - x0[idx] - w0[idx]))
		((dist >= -1 && dist <= 1)) && keep_idx=$idx
	fi
	# the sidebar is always a leaf column
	if [[ -n $sidebar_id && $c != *'['* ]]; then
		id=${c##*,}
		if [[ $id == "$sidebar_id" ]]; then
			issb[idx]=1; sb_w=${w0[idx]}; continue
		fi
	fi
	issb[idx]=0; nonsb=$((nonsb + 1))
done

[[ -n $mode ]] && ((keep_idx < 0)) && exit 0 # no matching column (e.g. a horizontal border) → leave as-is
# the kept column holds its width just like the sidebar (unless it *is* the sidebar)
if ((keep_idx >= 0)) && ((issb[keep_idx] == 0)); then
	issb[keep_idx]=1; sb_w=$((sb_w + w0[keep_idx])); nonsb=$((nonsb - 1))
fi

((nonsb >= 1)) || exit 0 # only the sidebar → nothing to do

# width left after kept columns and the (ncols-1) separators
avail=$((W - (ncols - 1) - sb_w))
((avail >= nonsb)) || fallback # too narrow for a clean tile → let tmux handle minima
base=$((avail / nonsb))
rem=$((avail - base * nonsb)) # spread the remainder across the first `rem` non-sidebar cols

# kept columns keep their width, others get base(+1); re-chain X
newcols=()
cursor=0
for idx in "${!cells[@]}"; do
	c=${cells[idx]}
	if ((${issb[idx]} == 1)); then
		wn=${w0[idx]}
	else
		wn=$base
		((rem > 0)) && { wn=$((base + 1)); rem=$((rem - 1)); }
	fi
	xn=$cursor
	# every cell in the column shares w0/x0: remap "<w0>x<h>,<x0>," → "<wn>x<h>,<xn>,"
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
