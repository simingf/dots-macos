#!/usr/bin/env bash
# tmux-layout-classic.sh <layout>: print a #{window_layout} in the classic "csum,WxH,X,Y{..}" form that
# tmux-even-columns.sh and tmux-lazygit.sh's _reclaim_layout parse. tmux ≥3.8 reports layouts as JSON
# ({"V":2,"L":{"t":"h|v|p","w","h","x","y","c":[..],"I":"%N"}}) but select-layout still accepts the
# classic form, so callers convert on read and keep rewriting classic strings. A classic input (older
# tmux) passes through unchanged. Exits 1 on what the classic form can't express — floating panes ("z")
# or anything unparseable — so callers treat it as an unsupported shape and leave the window alone.
set -uo pipefail

l=${1:-}
case $l in
  '{'*) ;;
  ?*) printf '%s\n' "$l"; exit 0 ;;
  *) exit 1 ;;
esac

awk -v s="$l" '
  function fail() { bad = 1; pos = length(s) + 1; return "" }
  function str(   e) {                              # at a quote: return the string, skip past it
    if (substr(s, pos, 1) != "\"") return fail()
    e = index(substr(s, pos + 1), "\"")
    if (!e) return fail()
    v = substr(s, pos + 1, e - 1); pos += e + 1; return v
  }
  function scalar(   c) {                           # number / true / false / string
    if (substr(s, pos, 1) == "\"") return str()
    v = ""
    while (pos <= length(s) && (c = substr(s, pos, 1)) !~ /[,}\]]/) { v = v c; pos++ }
    return v
  }
  function kids(   out, c) {                        # at "[": the comma-joined classic children
    pos++; out = ""
    while (pos <= length(s)) {
      c = substr(s, pos, 1)
      if (c == "]") { pos++; return out }
      if (c == ",") { pos++; continue }
      out = out (out == "" ? "" : ",") node()
    }
    return fail()
  }
  function node(   k, t, w, h, x, y, id, ch, inner, c) {  # at "{": one cell in classic form
    if (substr(s, pos, 1) != "{") return fail()
    pos++
    while (pos <= length(s)) {
      c = substr(s, pos, 1)
      if (c == "}") { pos++; break }
      if (c == ",") { pos++; continue }
      k = str(); if (substr(s, pos, 1) != ":") return fail(); pos++
      if (k == "L") inner = node()
      else if (k == "c") ch = kids()
      else {
        v = scalar()
        if (k == "t") t = v; else if (k == "w") w = v; else if (k == "h") h = v
        else if (k == "x") x = v; else if (k == "y") y = v; else if (k == "I") id = v
        else if (k == "z") bad = 1                  # floating pane
      }
    }
    if (inner != "") return inner                   # the {"V":..,"L":..} wrapper
    if (t == "p") return w "x" h "," x "," y "," substr(id, 2)
    if (t == "h") return w "x" h "," x "," y "{" ch "}"
    if (t == "v") return w "x" h "," x "," y "[" ch "]"
    return fail()
  }
  BEGIN {
    for (i = 32; i < 127; i++) ord[sprintf("%c", i)] = i
    pos = 1; body = node()
    if (bad || body == "") exit 1
    c = 0                                           # tmux layout_checksum (layout-custom.c)
    for (i = 1; i <= length(body); i++) c = (int(c / 2) + (c % 2) * 32768 + ord[substr(body, i, 1)]) % 65536
    printf "%04x,%s\n", c, body
  }'
