#!/usr/bin/env bash
# Vendor the Mac's zsh/nvim plugin trees + linux binaries into ~/dots-linux/vendor/,
# then commit vendor/ with SKIP=gitleaks. Normally run by refresh-linux.sh, which
# updates the plugin trees first.

set -Eeuo pipefail
trap 'echo "${0##*/}: FAILED (line $LINENO): $BASH_COMMAND" >&2' ERR
[[ $(uname) == Darwin ]] || { echo "${0##*/}: runs on the Mac (vendors its plugin trees; the dev box has no internet)" >&2; exit 1; }

DOTS_LINUX="${HOME}/dots-linux"
[ -d "$DOTS_LINUX" ] || { echo "dots-linux not found at $DOTS_LINUX" >&2; exit 1; }

# --delete prunes removed plugins; no nested .git so files are tracked, not submodules
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
  --dir "$TMPDIR" --clobber >/dev/null
tar -xzf "$TMPDIR/eza_x86_64-unknown-linux-musl.tar.gz" -C "$TMPDIR" ./eza
cp "$TMPDIR/eza" "$DOTS_LINUX/vendor/bin/eza"
echo "  eza ✓"

gh release download --repo ajeetdsouza/zoxide \
  --pattern 'zoxide-*-x86_64-unknown-linux-musl.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null
tar -xzf "$TMPDIR"/zoxide-*-x86_64-unknown-linux-musl.tar.gz -C "$TMPDIR" zoxide
cp "$TMPDIR/zoxide" "$DOTS_LINUX/vendor/bin/zoxide"
echo "  zoxide ✓"

gh release download --repo sxyazi/yazi \
  --pattern 'yazi-x86_64-unknown-linux-musl.zip' \
  --dir "$TMPDIR" --clobber >/dev/null
unzip -qo "$TMPDIR/yazi-x86_64-unknown-linux-musl.zip" \
  'yazi-x86_64-unknown-linux-musl/yazi' \
  'yazi-x86_64-unknown-linux-musl/ya' \
  -d "$TMPDIR"
cp "$TMPDIR/yazi-x86_64-unknown-linux-musl/yazi" "$DOTS_LINUX/vendor/bin/yazi"
cp "$TMPDIR/yazi-x86_64-unknown-linux-musl/ya"   "$DOTS_LINUX/vendor/bin/ya"
echo "  yazi, ya ✓"

# fzf: no musl asset, but linux_amd64 is static Go. Debian's apt fzf 0.44 is too old.
gh release download --repo junegunn/fzf \
  --pattern 'fzf-*-linux_amd64.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null
tar -xzf "$TMPDIR"/fzf-*-linux_amd64.tar.gz -C "$TMPDIR" fzf
cp "$TMPDIR/fzf" "$DOTS_LINUX/vendor/bin/fzf"
echo "  fzf ✓"

# glow: yazi's *.md previewer (glow.yazi)
gh release download --repo charmbracelet/glow \
  --pattern 'glow_*_Linux_x86_64.tar.gz' \
  --dir "$TMPDIR" --clobber >/dev/null
tar -xzf "$TMPDIR"/glow_*_Linux_x86_64.tar.gz -C "$TMPDIR"
# find exits 0 on no match — cp of an empty path fails instead.
glow=$(find "$TMPDIR" -type f -name glow | head -1)
cp "$glow" "$DOTS_LINUX/vendor/bin/glow"
echo "  glow ✓"

# oh-my-posh: zsh prompt (zen.toml); bare static binary
gh release download --repo JanDeDobbeleer/oh-my-posh \
  --pattern 'posh-linux-amd64' \
  --dir "$TMPDIR" --clobber >/dev/null
cp "$TMPDIR/posh-linux-amd64" "$DOTS_LINUX/vendor/bin/oh-my-posh"
echo "  oh-my-posh ✓"

# tmux: Debian's 3.4 lacks the pane-title-changed / window-layout-changed hooks
# (silently ignored). Fully-static build; shadows /usr/bin/tmux via ~/.local/bin.
gh release download --repo mjakob-gh/build-static-tmux \
  --pattern 'tmux.linux-amd64.stripped.gz' \
  --dir "$TMPDIR" --clobber >/dev/null
gunzip -c "$TMPDIR/tmux.linux-amd64.stripped.gz" > "$DOTS_LINUX/vendor/bin/tmux"
echo "  tmux ✓"

# rsvg-convert (new-diagram skill): apt installs vanish on restart and there's no
# static build, so take the binary from Ubuntu's .deb — its libs are already in the
# image (24.04 noble). Bump RSVG_DEB with the image's release.
RSVG_DEB=librsvg2-bin_2.58.0+dfsg-1ubuntu0.1_amd64.deb
curl -fsSL -o "$TMPDIR/$RSVG_DEB" "http://archive.ubuntu.com/ubuntu/pool/universe/libr/librsvg/$RSVG_DEB"
(cd "$TMPDIR" && ar x "$RSVG_DEB" data.tar.zst)
if command -v zstd >/dev/null; then
  zstd -dc "$TMPDIR/data.tar.zst" | tar -xf - -C "$TMPDIR" ./usr/bin/rsvg-convert
else
  tar -xf "$TMPDIR/data.tar.zst" -C "$TMPDIR" ./usr/bin/rsvg-convert  # bsdtar reads zstd itself
fi
cp "$TMPDIR/usr/bin/rsvg-convert" "$DOTS_LINUX/vendor/bin/rsvg-convert"
echo "  rsvg-convert ✓"

# ImageMagick (snacks.nvim images): same .deb route, IM6 + liblqr (the one missing
# lib). Its compiled-in /usr,/etc paths are redirected by dots-linux bin/magick via
# MAGICK_* env vars. Bump IM_VER / LQR_VER with the image's release.
IM_VER=6.9.12.98+dfsg1-5.2build2 LQR_VER=0.4.2-2.1build2
IM="$DOTS_LINUX/vendor/imagemagick"
UBU=http://archive.ubuntu.com/ubuntu/pool/universe
mkdir -p "$TMPDIR/im"
for deb in "i/imagemagick/imagemagick-6.q16_${IM_VER}_amd64" "i/imagemagick/libmagickcore-6.q16-7t64_${IM_VER}_amd64" \
           "i/imagemagick/libmagickwand-6.q16-7t64_${IM_VER}_amd64" "i/imagemagick/imagemagick-6-common_${IM_VER}_all" \
           "libl/liblqr/liblqr-1-0_${LQR_VER}_amd64"; do
  curl -fsSL -o "$TMPDIR/im.deb" "$UBU/$deb.deb"
  (cd "$TMPDIR" && ar x im.deb data.tar.zst)
  if command -v zstd >/dev/null; then
    zstd -dc "$TMPDIR/data.tar.zst" | tar -xf - -C "$TMPDIR/im"
  else
    tar -xf "$TMPDIR/data.tar.zst" -C "$TMPDIR/im"
  fi
  rm "$TMPDIR/im.deb" "$TMPDIR/data.tar.zst"
done
rm -rf "$IM" && mkdir -p "$IM/bin"
cp "$TMPDIR/im/usr/bin/convert-im6.q16" "$TMPDIR/im/usr/bin/identify-im6.q16" "$IM/bin/"
cp -R "$TMPDIR/im/usr/lib/x86_64-linux-gnu" "$IM/lib"
cp -RL "$TMPDIR/im/etc/ImageMagick-6" "$IM/etc"
cp -R "$TMPDIR/im/usr/share/ImageMagick-6" "$IM/share"
echo "  imagemagick ✓"

chmod +x "$DOTS_LINUX/vendor/bin"/{eza,zoxide,yazi,ya,fzf,glow,oh-my-posh,tmux,rsvg-convert} "$IM/bin"/*

# SKIP=gitleaks: vendor/ is all third-party bytes (SHAs, example IPs trip false
# positives). Pathspec-scoped so config commits are still scanned. No push here.
echo "==> committing vendor/"
git -C "$DOTS_LINUX" add -A vendor/
if git -C "$DOTS_LINUX" diff --cached --quiet -- vendor/; then
  echo "  nothing changed"
else
  SKIP=gitleaks git -C "$DOTS_LINUX" commit -q -m "vendor: refresh vendored plugins + binaries" -- vendor/
  echo "  committed (SKIP=gitleaks) — review & push from $DOTS_LINUX"
fi

echo "done."
