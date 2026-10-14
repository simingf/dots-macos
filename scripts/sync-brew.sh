#!/usr/bin/env bash
set -euo pipefail

BREWFILE="${1:-$HOME/dots-macos/Brewfile}"
TMPFILE=$(mktemp)
OLD=$(mktemp)
trap 'rm -f "$TMPFILE" "$OLD"' EXIT

brew bundle dump --force --tap --formula --cask --no-restart --file="$TMPFILE"

# Preserve the hand-maintained "Intentionally NOT casks" block (apps we
# deliberately don't let brew own — dump can't know about them).
NOTCASKS=""
if [[ -f "$BREWFILE" ]]; then
  NOTCASKS=$(awk '/^# ---- Intentionally NOT casks/{p=1} p' "$BREWFILE")
fi

# Keep an entry's existing Brewfile line verbatim when dump still lists it, so
# hand-added options dump can't know about (start_service:, trusted:) survive.
# Dump decides which entries exist; the old file only supplies their wording.
# (Snapshot first: the `> "$BREWFILE"` below truncates it before section runs.)
[[ -f "$BREWFILE" ]] && cp "$BREWFILE" "$OLD"
section() {
  awk -v kind="$1" '
    match($0, /^(tap|brew|cask) "[^"]+"/) { key = substr($0, RSTART, RLENGTH) }
    FNR == NR { if (RLENGTH > 0 && $1 == kind) old[key] = $0; next }
    $1 == kind { print (key in old ? old[key] : $0) }
  ' "$OLD" "$TMPFILE" | sort
}

{
  cat <<'EOF'
# file location: ${HOME}/dots-macos/Brewfile
# Usage: brew bundle install --file=~/dots-macos/Brewfile

# Install all casks to /Applications and adopt any existing app already present
cask_args appdir: "/Applications", fontdir: "/Library/Fonts", adopt: true

# ---- Taps ----
EOF
  section tap
  echo
  echo "# ---- Formulae ----"
  section brew
  echo
  echo "# ---- Casks ----"
  section cask | sed 's/, args: .*//'
  if [[ -n "$NOTCASKS" ]]; then
    echo
    printf '%s\n' "$NOTCASKS"
  fi
} > "$BREWFILE"

n_taps=$(grep -c '^tap ' "$BREWFILE" || true)
n_formulae=$(grep -c '^brew ' "$BREWFILE" || true)
n_casks=$(grep -c '^cask ' "$BREWFILE" || true)
echo "Wrote $BREWFILE: $n_taps taps, $n_formulae leaves, $n_casks casks."
