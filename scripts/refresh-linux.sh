#!/usr/bin/env bash
# One-shot "refresh Linux vendored plugins" — fully hands-off. Runs on macOS.
#
#   1. Update the Mac's own plugin trees (nvim lazy.nvim + zinit) — the source —
#      and herdr's Claude detection rules (tmux-agent-state.py update-rules; its
#      offline test must pass, else the refresh stops before anything is committed).
#   2. Re-vendor them (+ binaries) into dots-linux; refresh-linux-vendored.sh
#      commits vendor/ itself with SKIP=gitleaks (all third-party bytes trip the
#      infosec gitleaks pre-commit hook with false positives).
#   3. Propagate config (lazy-lock.json, etc.) into dots-linux via sync-dotfiles.
#   4. Commit + push both repos.
#
# Why the commit story is safe:
#  - vendor/ is committed in step 2 with SKIP=gitleaks (third-party FPs).
#  - Config commits here are scanned normally — lazy-lock's 40-hex SHAs don't
#    trip the rules (the token rule keys on the `revision = '…'` lua context, not
#    JSON), and a real hand-authored secret still hard-blocks.
#  - `git push` is never scanned: the infosec wrapper only gates `git commit`
#    (fast-paths everything else), so pushing the vendor commit is fine.
#
# Commits are pathspec-scoped to the refresh's footprint (nvim lazy-lock, agent
# detection rules) so this
# never sweeps unrelated pending work into a refresh commit. Anything else left
# dirty is printed at the end for you to handle.

set -Eeuo pipefail
trap 'echo "${0##*/}: FAILED (line $LINENO): $BASH_COMMAND" >&2' ERR
[[ $(uname) == Darwin ]] || { echo "${0##*/}: runs on the Mac (vendors its plugin trees; the dev box has no internet)" >&2; exit 1; }

DOTS_MACOS="${HOME}/dots-macos"
DOTS_LINUX="${HOME}/dots-linux"

# Force pagers off: zinit prints each plugin's git-log changelog, and git pipes
# `git log` through less on a TTY — which hangs the script waiting for `q`. The
# top-level export covers every step; the inline copy on the zinit line survives
# a zshrc that resets PAGER inside the interactive `zsh -ic`.
export GIT_PAGER=cat PAGER=cat

echo "==> [1/4] updating Mac plugin trees (nvim lazy + zinit) + agent detection rules"
# nvim exits 0 even when a plugin's fetch/checkout fails — check lazy's task errors.
nvim --headless +"Lazy! sync" +'lua local P, bad = require("lazy.core.plugin"), {}
  for n, p in pairs(require("lazy.core.config").plugins) do if P.has_errors(p) then bad[#bad + 1] = n end end
  if #bad > 0 then io.stderr:write("Lazy! sync failed: " .. table.concat(bad, ", ") .. "\n") vim.cmd("cquit 1") end' +qa
zsh -ic 'GIT_PAGER=cat PAGER=cat zinit update --all'
# Assign first: a failure inside $(...) in echo's args wouldn't trip set -e.
rules=$("$DOTS_MACOS/scripts/tmux-agent-state.py" update-rules)
echo "    herdr Claude detection rules: $rules"
"$DOTS_MACOS/scripts/test-agent-state.py" >/dev/null || { "$DOTS_MACOS/scripts/test-agent-state.py"; exit 1; }

echo "==> [2/4] vendoring into dots-linux (commits vendor/ with SKIP=gitleaks)"
"$DOTS_MACOS/scripts/refresh-linux-vendored.sh"

echo "==> [3/4] propagating config to dots-linux"
"$DOTS_MACOS/scripts/sync-dotfiles.py" --apply linux

echo "==> [4/4] commit + push"
# Stage+commit the given pathspec (scanned) if it changed, then push everything
# unpushed (incl. the SKIP'd vendor commit from step 2). push is never scanned.
commit_push() {
  local repo="$1" msg="$2"; shift 2
  git -C "$repo" add -- "$@"
  if git -C "$repo" diff --cached --quiet -- "$@"; then
    echo "  $(basename "$repo"): no config change to commit"
  else
    git -C "$repo" commit -q -m "$msg" -- "$@"
    echo "  $(basename "$repo"): committed config"
  fi
  git -C "$repo" push
  local leftover
  leftover=$(git -C "$repo" status --short)
  # `if`, not `&& printf`: a bare `[ -n "$leftover" ] && …` as the last statement
  # returns 1 when the tree is clean, which under `set -e` aborts the whole script.
  if [ -n "$leftover" ]; then
    printf '  %s: left uncommitted (handle manually):\n%s\n' "$(basename "$repo")" "$leftover"
  fi
}

commit_push "$DOTS_MACOS" "refresh: bump nvim lazy-lock + herdr Claude detection rules" \
  .config/nvim/lazy-lock.json scripts/agent-detection
commit_push "$DOTS_LINUX" "refresh: sync nvim lazy-lock + herdr Claude detection rules" \
  .config/nvim scripts/agent-detection

echo "done."
