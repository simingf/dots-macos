#!/usr/bin/env bash
# One-shot "refresh Linux vendored plugins" (Mac only; see CLAUDE.md "Sync workflow"):
#   1. update the Mac's nvim lazy + zinit trees and herdr's Claude rules (test must pass)
#   2. re-vendor into dots-linux (refresh-linux-vendored.sh commits vendor/, SKIP=gitleaks)
#   3. sync-dotfiles.py --apply linux
#   4. commit (gitleaks-scanned, pathspec-scoped to the refresh) + push both repos
#      (push is never scanned)

set -Eeuo pipefail
trap 'echo "${0##*/}: FAILED (line $LINENO): $BASH_COMMAND" >&2' ERR
[[ $(uname) == Darwin ]] || { echo "${0##*/}: runs on the Mac (vendors its plugin trees; the dev box has no internet)" >&2; exit 1; }

DOTS_MACOS="${HOME}/dots-macos"
DOTS_LINUX="${HOME}/dots-linux"

# No pagers: zinit's git-log changelogs would hang in less.
export GIT_PAGER=cat PAGER=cat

echo "==> [1/4] updating Mac plugin trees (nvim lazy + zinit) + agent detection rules"
# zinit runs alongside lazy (independent trees): parallel jobs, sourcing zinit alone instead of a full
# `zsh -ic` startup; its output is replayed after lazy's so the two don't interleave.
ZPLUG=~/.local/share/zinit/plugins
zheads() { for d in "$ZPLUG"/[!_]*/; do printf '%s %s\n' "$(basename "$d")" "$(git -C "$d" rev-parse --short HEAD)"; done | LC_ALL=C sort; }
zbefore=$(zheads)
zlog=$(mktemp)
zsh -c 'source ~/.local/share/zinit/zinit.git/zinit.zsh && GIT_PAGER=cat PAGER=cat zinit update --parallel' >"$zlog" 2>&1 &
zpid=$!
# nvim exits 0 even when a plugin's fetch/checkout fails — check lazy's task errors.
nvim --headless +"Lazy! sync" +'lua local P, bad = require("lazy.core.plugin"), {}
  for n, p in pairs(require("lazy.core.config").plugins) do if P.has_errors(p) then bad[#bad + 1] = n end end
  if #bad > 0 then io.stderr:write("Lazy! sync failed: " .. table.concat(bad, ", ") .. "\n") vim.cmd("cquit 1") end' +qa
zst=0; wait "$zpid" || zst=$?
cat "$zlog"; rm -f "$zlog"
[ "$zst" -eq 0 ] || { echo "zinit update failed (exit $zst)" >&2; exit 1; }
# --parallel doesn't list plugins, so report each one's HEAD change
join <(echo "$zbefore") <(zheads) | while read -r name old new; do
  [ "$old" = "$new" ] && echo "  ${name/---//}: up to date" || echo "  ${name/---//}: $old → $new"
done
# Assign first: a failure inside $(...) in echo's args wouldn't trip set -e.
rules=$("$DOTS_MACOS/scripts/tmux-agent-state.py" update-rules)
echo "    herdr Claude detection rules: $rules"
"$DOTS_MACOS/scripts/test-agent-state.py" >/dev/null || { "$DOTS_MACOS/scripts/test-agent-state.py"; exit 1; }

echo "==> [2/4] vendoring into dots-linux (commits vendor/ with SKIP=gitleaks)"
"$DOTS_MACOS/scripts/refresh-linux-vendored.sh"

echo "==> [3/4] propagating config to dots-linux"
"$DOTS_MACOS/scripts/sync-dotfiles.py" --apply linux

echo "==> [4/4] commit + push"
# Commit the pathspec if changed, then push everything (incl. step 2's vendor commit)
commit_push() {
  local repo="$1" msg="$2"; shift 2
  git -C "$repo" add -- "$@"
  if git -C "$repo" diff --cached --quiet -- "$@"; then
    echo "  $(basename "$repo"): no config change to commit"
  else
    git -C "$repo" commit -q -m "$msg" -- "$@"
    echo "  $(basename "$repo"): committed config"
  fi
  # drop GHE's known large-file warning (vendored gopls ~29MB > the 25MB recommendation; hard cap is 100MB)
  git -C "$repo" push 2> >(grep -v -E 'remote: warning: (Please visit https://roblox\.atlassian|File vendor/.* is .* recommended maximum|GH001: Large files detected)' >&2)
  local leftover
  leftover=$(git -C "$repo" status --short)
  # `if`, not `&&`: as the last statement it'd return 1 on a clean tree → set -e abort
  if [ -n "$leftover" ]; then
    printf '  %s: left uncommitted (handle manually):\n%s\n' "$(basename "$repo")" "$leftover"
  fi
}

commit_push "$DOTS_MACOS" "refresh: bump nvim lazy-lock + herdr Claude detection rules" \
  .config/nvim/lazy-lock.json scripts/agent-detection
commit_push "$DOTS_LINUX" "refresh: sync nvim lazy-lock + herdr Claude detection rules" \
  .config/nvim scripts/agent-detection

echo "done."
