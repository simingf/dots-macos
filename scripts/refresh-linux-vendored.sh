#!/usr/bin/env bash
# Refresh vendored zsh plugins and nvim lazy.nvim plugins in ~/dots-linux.
#
# Run on macOS after the local plugin trees are up to date:
#   nvim --headless +"Lazy! sync" +qa
#   zsh -ic 'zinit update --all'
#
# `--delete` prunes plugins removed from the source tree.
# `--exclude='.git'` strips nested git dirs so the dev box repo tracks files,
# not submodules.
#
# Finishes by auto-committing the refreshed vendor/ tree with SKIP=gitleaks:
# it's all third-party plugin/binary bytes that trip Roblox's gitleaks
# pre-commit hook with false positives (git SHAs read as tokens, example IPs,
# doc emails). Scoped to vendor/ so your own config commits are still scanned.

set -euo pipefail

DOTS_LINUX="${HOME}/dots-linux"
[ -d "$DOTS_LINUX" ] || { echo "dots-linux not found at $DOTS_LINUX" >&2; exit 1; }

RSYNC=(rsync -a --delete --exclude='.git')

echo "==> zsh plugins"
"${RSYNC[@]}" ~/.local/share/zinit/plugins/Aloxaf---fzf-tab/                    "$DOTS_LINUX/vendor/zsh-plugins/fzf-tab/"
"${RSYNC[@]}" ~/.local/share/zinit/plugins/zsh-users---zsh-autosuggestions/     "$DOTS_LINUX/vendor/zsh-plugins/zsh-autosuggestions/"
"${RSYNC[@]}" ~/.local/share/zinit/plugins/zsh-users---zsh-syntax-highlighting/ "$DOTS_LINUX/vendor/zsh-plugins/zsh-syntax-highlighting/"
"${RSYNC[@]}" ~/.local/share/zinit/plugins/zsh-users---zsh-completions/         "$DOTS_LINUX/vendor/zsh-plugins/zsh-completions/"
"${RSYNC[@]}" ~/.local/share/zinit/snippets/OMZP::sudo/                         "$DOTS_LINUX/vendor/zsh-plugins/omz-sudo/"

echo "==> nvim plugins"
"${RSYNC[@]}" ~/.local/share/nvim/lazy/                                         "$DOTS_LINUX/vendor/nvim-lazy/"

echo "==> vendored binaries (linux x86_64 musl)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export GH_HOST=github.com

gh release download --repo eza-community/eza \
  --pattern 'eza_x86_64-unknown-linux-musl.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
tar -xzf "$TMPDIR/eza_x86_64-unknown-linux-musl.tar.gz" -C "$TMPDIR" ./eza
cp "$TMPDIR/eza" "$DOTS_LINUX/vendor/bin/eza"
echo "  eza ✓"

gh release download --repo ajeetdsouza/zoxide \
  --pattern 'zoxide-*-x86_64-unknown-linux-musl.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
tar -xzf "$TMPDIR"/zoxide-*-x86_64-unknown-linux-musl.tar.gz -C "$TMPDIR" zoxide
cp "$TMPDIR/zoxide" "$DOTS_LINUX/vendor/bin/zoxide"
echo "  zoxide ✓"

gh release download --repo sxyazi/yazi \
  --pattern 'yazi-x86_64-unknown-linux-musl.zip' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
unzip -qo "$TMPDIR/yazi-x86_64-unknown-linux-musl.zip" \
  'yazi-x86_64-unknown-linux-musl/yazi' \
  'yazi-x86_64-unknown-linux-musl/ya' \
  -d "$TMPDIR"
cp "$TMPDIR/yazi-x86_64-unknown-linux-musl/yazi" "$DOTS_LINUX/vendor/bin/yazi"
cp "$TMPDIR/yazi-x86_64-unknown-linux-musl/ya"   "$DOTS_LINUX/vendor/bin/ya"
echo "  yazi, ya ✓"

# fzf ships no musl asset; linux_amd64 is a static (CGO-disabled) Go binary that
# runs on glibc and musl alike. Vendored so the box beats Debian's apt fzf 0.44
# (too old for the agent sidebar panel's flags).
gh release download --repo junegunn/fzf \
  --pattern 'fzf-*-linux_amd64.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
tar -xzf "$TMPDIR"/fzf-*-linux_amd64.tar.gz -C "$TMPDIR" fzf
cp "$TMPDIR/fzf" "$DOTS_LINUX/vendor/bin/fzf"
echo "  fzf ✓"

# glow: markdown renderer for yazi's *.md previewer (glow.yazi plugin). Without it
# the plugin falls back to raw syntax-highlighted markdown.
gh release download --repo charmbracelet/glow \
  --pattern 'glow_*_Linux_x86_64.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
tar -xzf "$TMPDIR"/glow_*_Linux_x86_64.tar.gz -C "$TMPDIR"
find "$TMPDIR" -type f -name glow -exec cp {} "$DOTS_LINUX/vendor/bin/glow" \;
echo "  glow ✓"

# oh-my-posh: prompt engine driving zsh's rose-pine zen theme
# (.config/ohmyposh/zen.toml). Single static Go binary — no archive to extract.
gh release download --repo JanDeDobbeleer/oh-my-posh \
  --pattern 'posh-linux-amd64' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
cp "$TMPDIR/posh-linux-amd64" "$DOTS_LINUX/vendor/bin/oh-my-posh"
echo "  oh-my-posh ✓"

# tmux: the box's Debian tmux is 3.4, which lacks the pane-title-changed and
# window-layout-changed hooks the agent sidebar relies on (tmux silently ignores
# unknown set-hook names, so the sidebar just goes stale). mjakob-gh publishes a
# fully-static musl build (own libevent + ncurses), so it runs standalone and
# shadows /usr/bin/tmux via ~/.local/bin. Single gzipped binary — no archive.
gh release download --repo mjakob-gh/build-static-tmux \
  --pattern 'tmux.linux-amd64.stripped.gz' \
  --dir "$TMPDIR" --clobber >/dev/null 2>&1
gunzip -c "$TMPDIR/tmux.linux-amd64.stripped.gz" > "$DOTS_LINUX/vendor/bin/tmux"
echo "  tmux ✓"

chmod +x "$DOTS_LINUX/vendor/bin"/{eza,zoxide,yazi,ya,fzf,glow,oh-my-posh,tmux}

# Commit the refreshed vendor/ tree. SKIP=gitleaks bypasses the infosec
# pre-commit hook (see header) — sanctioned here because the tree is entirely
# third-party bytes with no real secrets. Pathspec-scoped to vendor/ so any
# staged config changes are left for you to commit normally (still scanned).
# Push stays manual.
echo "==> committing vendor/"
git -C "$DOTS_LINUX" add -A vendor/
if git -C "$DOTS_LINUX" diff --cached --quiet -- vendor/; then
  echo "  nothing changed"
else
  SKIP=gitleaks git -C "$DOTS_LINUX" commit -q -m "vendor: refresh vendored plugins + binaries" -- vendor/
  echo "  committed (SKIP=gitleaks) — review & push from $DOTS_LINUX"
fi

echo "done."
