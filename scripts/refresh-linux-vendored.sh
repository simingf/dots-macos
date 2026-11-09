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

# Each item is fetched only when its version differs from vendor/VERSIONS (name=version lines),
# so an unchanged refresh downloads nothing. vendor <name> <version> <fetch-fn>: fetch-fn gets the version.
VERSIONS="$DOTS_LINUX/vendor/VERSIONS"
touch "$VERSIONS"
vendor() {
  [[ -n $2 ]] || { echo "  $1: couldn't resolve a version" >&2; exit 1; }
  if [[ $(sed -n "s/^$1=//p" "$VERSIONS") == "$2" ]]; then echo "  $1 $2 (unchanged) ✓"; return; fi
  "$3" "$2"
  { grep -v "^$1=" "$VERSIONS" || true; echo "$1=$2"; } | sort > "$TMPDIR/VERSIONS" && mv "$TMPDIR/VERSIONS" "$VERSIONS"
  echo "  $1 $2 ✓"
}
latest() { gh release view --repo "$1" --json tagName --jq .tagName; }
dl() { gh release download "$1" --repo "$2" --pattern "$3" --dir "$TMPDIR" --clobber >/dev/null; }   # <tag> <repo> <pattern>

fetch_eza() {
  dl "$1" eza-community/eza 'eza_x86_64-unknown-linux-musl.tar.gz'
  tar -xzf "$TMPDIR/eza_x86_64-unknown-linux-musl.tar.gz" -C "$TMPDIR" ./eza
  cp "$TMPDIR/eza" "$DOTS_LINUX/vendor/bin/eza"
}
vendor eza "$(latest eza-community/eza)" fetch_eza

fetch_zoxide() {
  dl "$1" ajeetdsouza/zoxide 'zoxide-*-x86_64-unknown-linux-musl.tar.gz'
  tar -xzf "$TMPDIR"/zoxide-*-x86_64-unknown-linux-musl.tar.gz -C "$TMPDIR" zoxide
  cp "$TMPDIR/zoxide" "$DOTS_LINUX/vendor/bin/zoxide"
}
vendor zoxide "$(latest ajeetdsouza/zoxide)" fetch_zoxide

fetch_yazi() {
  dl "$1" sxyazi/yazi 'yazi-x86_64-unknown-linux-musl.zip'
  unzip -qo "$TMPDIR/yazi-x86_64-unknown-linux-musl.zip" \
    'yazi-x86_64-unknown-linux-musl/yazi' 'yazi-x86_64-unknown-linux-musl/ya' -d "$TMPDIR"
  cp "$TMPDIR/yazi-x86_64-unknown-linux-musl/yazi" "$DOTS_LINUX/vendor/bin/yazi"
  cp "$TMPDIR/yazi-x86_64-unknown-linux-musl/ya"   "$DOTS_LINUX/vendor/bin/ya"
}
vendor yazi "$(latest sxyazi/yazi)" fetch_yazi

# fzf: no musl asset, but linux_amd64 is static Go. Debian's apt fzf 0.44 is too old.
fetch_fzf() {
  dl "$1" junegunn/fzf 'fzf-*-linux_amd64.tar.gz'
  tar -xzf "$TMPDIR"/fzf-*-linux_amd64.tar.gz -C "$TMPDIR" fzf
  cp "$TMPDIR/fzf" "$DOTS_LINUX/vendor/bin/fzf"
}
vendor fzf "$(latest junegunn/fzf)" fetch_fzf

# glow: yazi's *.md previewer (glow.yazi)
fetch_glow() {
  dl "$1" charmbracelet/glow 'glow_*_Linux_x86_64.tar.gz'
  tar -xzf "$TMPDIR"/glow_*_Linux_x86_64.tar.gz -C "$TMPDIR"
  local glow; glow=$(find "$TMPDIR" -type f -name glow | head -1)   # find exits 0 on no match; cp of "" fails instead
  cp "$glow" "$DOTS_LINUX/vendor/bin/glow"
}
vendor glow "$(latest charmbracelet/glow)" fetch_glow

# lazygit: the image's /usr/local/bin one lags the Mac's brew (0.59 ignores gui.theme.authorColors); static Go
fetch_lazygit() {
  dl "$1" jesseduffield/lazygit 'lazygit_*_linux_x86_64.tar.gz'
  tar -xzf "$TMPDIR"/lazygit_*_linux_x86_64.tar.gz -C "$TMPDIR" lazygit
  cp "$TMPDIR/lazygit" "$DOTS_LINUX/vendor/bin/lazygit"
}
vendor lazygit "$(latest jesseduffield/lazygit)" fetch_lazygit

# oh-my-posh: zsh prompt (zen.toml); bare static binary
fetch_posh() {
  dl "$1" JanDeDobbeleer/oh-my-posh 'posh-linux-amd64'
  cp "$TMPDIR/posh-linux-amd64" "$DOTS_LINUX/vendor/bin/oh-my-posh"
}
vendor oh-my-posh "$(latest JanDeDobbeleer/oh-my-posh)" fetch_posh

# tmux: Debian's 3.4 lacks the pane-title-changed / window-layout-changed hooks
# (silently ignored). Fully-static build; shadows /usr/bin/tmux via ~/.local/bin.
fetch_tmux() {
  dl "$1" mjakob-gh/build-static-tmux 'tmux.linux-amd64.stripped.gz'
  gunzip -c "$TMPDIR/tmux.linux-amd64.stripped.gz" > "$DOTS_LINUX/vendor/bin/tmux"
}
vendor tmux "$(latest mjakob-gh/build-static-tmux)" fetch_tmux

# .deb data.tar.zst → dir (zstd if present, else bsdtar reads zstd itself)
deb_extract() {   # <deb> <dest> [paths…]
  local deb=$1 dest=$2; shift 2
  (cd "$TMPDIR" && ar x "$deb" data.tar.zst)
  if command -v zstd >/dev/null; then zstd -dc "$TMPDIR/data.tar.zst" | tar -xf - -C "$dest" "$@"
  else tar -xf "$TMPDIR/data.tar.zst" -C "$dest" "$@"; fi
  rm "$TMPDIR/data.tar.zst"
}

# rsvg-convert (new-diagram skill): apt installs vanish on restart and there's no
# static build, so take the binary from Ubuntu's .deb — its libs are already in the
# image (24.04 noble). Bump RSVG_DEB with the image's release.
RSVG_DEB=librsvg2-bin_2.58.0+dfsg-1ubuntu0.1_amd64.deb
fetch_rsvg() {
  curl -fsSL -o "$TMPDIR/$RSVG_DEB" "http://archive.ubuntu.com/ubuntu/pool/universe/libr/librsvg/$RSVG_DEB"
  deb_extract "$RSVG_DEB" "$TMPDIR" ./usr/bin/rsvg-convert
  cp "$TMPDIR/usr/bin/rsvg-convert" "$DOTS_LINUX/vendor/bin/rsvg-convert"
}
vendor rsvg-convert "$RSVG_DEB" fetch_rsvg

# ImageMagick (snacks.nvim images): same .deb route, IM6 + liblqr (the one missing
# lib). Its compiled-in /usr,/etc paths are redirected by dots-linux bin/magick via
# MAGICK_* env vars. Bump IM_VER / LQR_VER with the image's release.
IM_VER=6.9.12.98+dfsg1-5.2build2 LQR_VER=0.4.2-2.1build2
IM="$DOTS_LINUX/vendor/imagemagick"
fetch_im() {
  local UBU=http://archive.ubuntu.com/ubuntu/pool/universe deb
  mkdir -p "$TMPDIR/im"
  for deb in "i/imagemagick/imagemagick-6.q16_${IM_VER}_amd64" "i/imagemagick/libmagickcore-6.q16-7t64_${IM_VER}_amd64" \
             "i/imagemagick/libmagickwand-6.q16-7t64_${IM_VER}_amd64" "i/imagemagick/imagemagick-6-common_${IM_VER}_all" \
             "libl/liblqr/liblqr-1-0_${LQR_VER}_amd64"; do
    curl -fsSL -o "$TMPDIR/im.deb" "$UBU/$deb.deb"
    deb_extract im.deb "$TMPDIR/im"
    rm "$TMPDIR/im.deb"
  done
  rm -rf "$IM" && mkdir -p "$IM/bin"
  cp "$TMPDIR/im/usr/bin/convert-im6.q16" "$TMPDIR/im/usr/bin/identify-im6.q16" "$IM/bin/"
  cp -R "$TMPDIR/im/usr/lib/x86_64-linux-gnu" "$IM/lib"
  cp -RL "$TMPDIR/im/etc/ImageMagick-6" "$IM/etc"
  cp -R "$TMPDIR/im/usr/share/ImageMagick-6" "$IM/share"
}
vendor imagemagick "$IM_VER+lqr$LQR_VER" fetch_im

# LSP servers (nvim's plugins/lsp.lua list), at the Mac mason versions so both hosts match. The box
# already has rust-analyzer, clangd-20 (dots-linux bin/clangd picks it), node and dotnet; the
# dots-linux bin/ wrappers run these. mason_ver <pkg> → version from the Mac's mason receipt.
echo "==> LSP servers"
MASON=~/.local/share/nvim/mason/packages
LSP="$DOTS_LINUX/vendor/lsp"
mkdir -p "$LSP"
mason_ver() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source"]["id"].rsplit("@",1)[1])' "$MASON/$1/mason-receipt.json"; }

for p in pyright bash-language-server; do   # pure JS: the Mac's mason install runs as-is on the box's node (local rsync, no download)
  "${RSYNC[@]}" --exclude='mason-*' "$MASON/$p/" "$LSP/$p/"
done
echo "  pyright $(mason_ver pyright), bash-language-server $(mason_ver bash-language-server) ✓"

fetch_luals() {
  dl "$1" LuaLS/lua-language-server "lua-language-server-$1-linux-x64.tar.gz"
  rm -rf "$LSP/lua-language-server" && mkdir -p "$LSP/lua-language-server"
  tar -xzf "$TMPDIR/lua-language-server-$1-linux-x64.tar.gz" -C "$LSP/lua-language-server"
}
vendor lua-language-server "$(mason_ver lua-language-server)" fetch_luals

# cross-compiled; GOPATH only for the output, modules come from the Mac's persistent cache
fetch_gopls() {
  local modcache; modcache=$(go env GOMODCACHE)   # before GOPATH is overridden, which would move it
  GOPATH="$TMPDIR/go" GOMODCACHE="$modcache" GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
    go install -trimpath -ldflags='-s -w' "golang.org/x/tools/gopls@$1"
  cp "$TMPDIR/go/bin/linux_amd64/gopls" "$DOTS_LINUX/vendor/bin/gopls"
}
vendor gopls "$(mason_ver gopls)" fetch_gopls

# roslyn: mason's version (registry, since the Mac has no dotnet → nothing installed), linux-x64 nupkg.
# Needs .NET ≥10 on the box. Locales / pdbs / doc xml / the .NET Framework build host are dropped.
fetch_roslyn() {
  curl -fsSL -o "$TMPDIR/roslyn.nupkg" "https://www.nuget.org/api/v2/package/roslyn-language-server.linux-x64/$1"
  rm -rf "$LSP/roslyn" "$TMPDIR/roslyn" && unzip -q "$TMPDIR/roslyn.nupkg" -d "$TMPDIR/roslyn"
  mv "$TMPDIR/roslyn/tools/net10.0/linux-x64" "$LSP/roslyn"
  (cd "$LSP/roslyn" && rm -rf BuildHost-net472 cs de es fr it ja ko pl pt-BR ru tr zh-Hans zh-Hant \
    && find . \( -name '*.pdb' -o -name '*.xml' ! -name DotnetToolSettings.xml \) -delete \
    && chmod +x roslyn-language-server Microsoft.CodeAnalysis.LanguageServer)   # unzip drops the apphosts' exec bit
}
vendor roslyn-language-server "$(gh api repos/mason-org/mason-registry/contents/packages/roslyn-language-server/package.yaml \
  --jq .content | base64 -d | sed -n 's/.*pkg:nuget\/roslyn-language-server@//p')" fetch_roslyn

chmod +x "$DOTS_LINUX/vendor/bin"/{eza,zoxide,yazi,ya,fzf,glow,lazygit,oh-my-posh,tmux,rsvg-convert,gopls} "$IM/bin"/*

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
