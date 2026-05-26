#!/usr/bin/env bash
set -euo pipefail

BREWFILE="${1:-$HOME/dots-macos/Brewfile}"

if [[ ! -f "$BREWFILE" ]]; then
  echo "Brewfile not found: $BREWFILE" >&2
  exit 1
fi

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

brew bundle dump --force --formula --cask --no-restart --file="$TMPFILE"

brewfile_formulae=$(grep '^brew ' "$BREWFILE" | sed 's/^brew "\([^"]*\)".*/\1/' | sort)
brewfile_casks=$(grep '^cask ' "$BREWFILE" | sed 's/^cask "\([^"]*\)".*/\1/' | sort)

installed_formulae=$(grep '^brew ' "$TMPFILE" | sed 's/^brew "\([^"]*\)".*/\1/' | sort)
installed_casks=$(grep '^cask ' "$TMPFILE" | sed 's/^cask "\([^"]*\)".*/\1/' | sort)

formula_only_brewfile=$(comm -23 <(echo "$brewfile_formulae") <(echo "$installed_formulae"))
formula_only_installed=$(comm -13 <(echo "$brewfile_formulae") <(echo "$installed_formulae"))
cask_only_brewfile=$(comm -23 <(echo "$brewfile_casks") <(echo "$installed_casks"))
cask_only_installed=$(comm -13 <(echo "$brewfile_casks") <(echo "$installed_casks"))

exit_code=0

print_diff() {
  local label="$1" items="$2"
  if [[ -n "$items" ]]; then
    echo "$label"
    echo "$items" | sed 's/^/  /'
    exit_code=1
  fi
}

print_diff "Formulae in Brewfile but not installed:" "$formula_only_brewfile"
print_diff "Formulae installed but not in Brewfile:" "$formula_only_installed"
print_diff "Casks in Brewfile but not installed:"    "$cask_only_brewfile"
print_diff "Casks installed but not in Brewfile:"    "$cask_only_installed"

n_formulae=$(echo "$installed_formulae" | wc -l | tr -d ' ')
n_casks=$(echo "$installed_casks" | wc -l | tr -d ' ')
echo "$n_formulae formulae, $n_casks casks installed."

if [[ $exit_code -eq 0 ]]; then
  echo "Brewfile is in sync."
fi

exit $exit_code
