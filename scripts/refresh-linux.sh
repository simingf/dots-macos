#!/usr/bin/env bash
# One-shot "refresh Linux vendored plugins" — fully hands-off. Runs on macOS.
#
#   1. Update the Mac's own plugin trees (nvim lazy.nvim + zinit) — the source.
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
# Commits are pathspec-scoped to the refresh's footprint (nvim lazy-lock) so this
# never sweeps unrelated pending work into a refresh commit. Anything else left
# dirty is printed at the end for you to handle.

set -euo pipefail

DOTS_MACOS="${HOME}/dots-macos"
DOTS_LINUX="${HOME}/dots-linux"

echo "==> [1/4] updating Mac plugin trees (nvim lazy + zinit)"
nvim --headless +"Lazy! sync" +qa
zsh -ic 'zinit update --all' || true  # zinit exits non-zero on 'nothing to update'

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
  [ -n "$leftover" ] && printf '  %s: left uncommitted (handle manually):\n%s\n' \
    "$(basename "$repo")" "$leftover"
}

commit_push "$DOTS_MACOS" "nvim: bump lazy-lock (plugin refresh)" .config/nvim/lazy-lock.json
commit_push "$DOTS_LINUX" "nvim: sync lazy-lock (plugin refresh)" .config/nvim

echo "done."
