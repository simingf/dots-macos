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

chmod +x "$DOTS_LINUX/vendor/bin"/{eza,zoxide,yazi,ya}

echo "done."
