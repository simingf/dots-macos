#!/usr/bin/env bash
# prefix f (inside `display-popup -E`): fuzzy-search the last 5000 lines of every pane (skipping `_*`
# sessions), preview the hit in context, then switch to that pane. fzf --exact so the preview's iris
# highlight matches fzf's. The target is NOT put in copy-mode (that traps keys until q).
set -euo pipefail

us=$(printf '\037')                       # field delimiter unlikely to appear in pane output

# --- preview sub-invocation: `… --preview <pane_id> <lineno> <query…>` (called by fzf) ---
# ±8 lines around <lineno>, hit line marked ▶, each query term (literal, case-insensitive) in iris.
# $snapdir is exported by the parent.
if [ "${1:-}" = "--preview" ]; then
    pid=$2; ln=$3; shift 3; query="$*"
    snap="$snapdir/${pid#%}"
    [ -f "$snap" ] || exit 0
    awk -v c="$ln" -v r=8 -v q="$query" '
    function hl(line,   low,n,i,k,p,start,nt,terms,t,tl,lt,out) {
      n = length(line); if (n == 0 || q == "") return line
      split("", mark); low = tolower(line); nt = split(q, terms, " ")
      for (t = 1; t <= nt; t++) {
        tl = length(terms[t]); if (tl == 0) continue
        lt = tolower(terms[t]); start = 1
        while ((p = index(substr(low, start), lt)) > 0) {
          for (k = 0; k < tl; k++) mark[start + p - 1 + k] = 1
          start = start + p - 1 + tl
        }
      }
      out = ""; i = 1
      while (i <= n) {
        if (i in mark) { out = out "\033[38;2;206;172;246m"; while (i <= n && (i in mark)) { out = out substr(line, i, 1); i++ }; out = out "\033[0m" }
        else { out = out substr(line, i, 1); i++ }
      }
      return out
    }
    NR >= c - r && NR <= c + r { printf "%s%s\n", (NR == c ? "▶ " : "  "), hl($0) }
    ' "$snap"
    exit 0
fi

# --- main: snapshot each pane, run the picker ---
snapdir=$(mktemp -d)
trap 'rm -rf "$snapdir"' EXIT
export snapdir
self="${BASH_SOURCE[0]}"; export self

# Snapshot each pane to $snapdir/<id>, then emit one fzf row per non-blank line:
#   <pane_id><US><lineno><US><loc + text>   — only the 3rd field is shown and searched.
sel=$(
  tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
  | grep -v '^[^ ]* _' \
  | while read -r pid loc; do
      snap="$snapdir/${pid#%}"
      tmux capture-pane -p -J -S -5000 -t "$pid" 2>/dev/null > "$snap" || continue
      awk -v pid="$pid" -v loc="$loc" -v us="$us" \
          'NF { printf "%s%s%d%s%-16s %s\n", pid, us, NR, us, loc, $0 }' "$snap"
    done \
  | fzf --delimiter="$us" --with-nth=3 --prompt='content> ' --exact \
        --color='hl:#ceacf6,hl+:#ceacf6,prompt:#ceacf6' \
        --preview-window='right:55%:wrap' \
        --preview='"$self" --preview {1} {2} {q}'
) || exit 0
[ -z "$sel" ] && exit 0

pid=${sel%%"$us"*}                        # field 1: pane id
session=$(tmux display-message -pt "$pid" '#{session_name}')
tmux switch-client -t "$session"
tmux select-window -t "$pid"
tmux select-pane   -t "$pid"
