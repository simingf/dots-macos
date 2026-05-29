#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")/.." && pwd)"

step() { echo "==> $*"; }

step "Disable press-and-hold (tilde key)"
defaults write -g ApplePressAndHoldEnabled -bool false

step "Hide Dock"
defaults write com.apple.dock autohide-delay -float 1000
killall Dock 2>/dev/null || true

step "git-lfs system install"
git lfs install --system

step "Dotfiles (stow)"
touch ~/.hushlogin

# stow refuses to overwrite real (non-symlink) files. Remove any in $HOME that
# would conflict — assumed to be Mac defaults on a fresh box.
( cd "$DOTS" && find . -type f \
    -not -path './.git/*' \
    -not -path './scripts/*' \
    -not -path './manual/*' \
    -not -path './ssh-dots/*' \
    -not -name '.DS_Store' \
    -not -name 'README.md' \
    -not -name 'WORK.md' \
    -not -name 'CLAUDE.md' \
) | while IFS= read -r f; do
  target="$HOME/${f#./}"
  [ -e "$target" ] || continue
  # Skip if target already resolves into $DOTS (stow tree-folds parent dirs
  # into symlinks, so a plain `-L` test on the leaf misses these).
  real=$(realpath "$target" 2>/dev/null || true)
  case "$real" in "$DOTS"/*) continue;; esac
  echo "  rm $target"
  rm -f "$target"
done

# Pre-create dirs that should be file-level symlinked (so stow doesn't tree-fold
# the whole dir, which would capture runtime state like OAuth tokens / sockets).
mkdir -p "$HOME/.config/portpal" "$HOME/.config/spotify-player"

stow --dir="$DOTS" --target="$HOME" .

step "Homebrew bundle"
brew bundle install --file="$DOTS/Brewfile"

step "Rust toolchain (rustup) + cargo binaries"
rustup default stable
cargo install spotify_player --features image,notify --locked

step "ani-cli (not in Homebrew)"
if ! command -v ani-cli >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  git clone --depth=1 https://github.com/pystardust/ani-cli.git "$tmp/ani-cli"
  install -m 0755 "$tmp/ani-cli/ani-cli" "$(brew --prefix)/bin/ani-cli"
  /bin/rm -rf "$tmp"
fi

step "Default file handlers (Launch Services plist)"
# We patch ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
# directly instead of shelling out to `duti`, for two reasons:
#
# 1. `duti` only writes LSHandlerRoleEditor, but macOS resolves defaults using
#    LSHandlerRoleAll first. If a competing app (e.g. Cursor) declares itself
#    as RoleAll, duti's RoleEditor write is silently ignored and the competitor
#    keeps winning. We write RoleAll directly.
#
# 2. Many extensions (.toml/.lua/.conf/.go/.tsx/.jsx/.ini/.env) have no stable
#    public UTI, so macOS synthesizes a dynamic one like `dyn.ah62d4rv4ge80s52`.
#    `duti` guesses a *different* dynamic UTI than what real files get tagged
#    with, so the setting silently misses. We probe the real UTI with `mdls`
#    on a throwaway tempfile.
#
# One case we can't fix here: Cursor's Info.plist declares `LSHandlerRank: Owner`
# for .json, which outranks any user preference. `.json` keeps opening in Cursor
# unless we edit and re-sign Cursor's bundle — not worth it for one extension.
python3 - "$DOTS/scripts/duti.conf" <<'PY'
import plistlib, subprocess, sys, tempfile, os
from pathlib import Path

conf = Path(sys.argv[1])
plist = Path.home() / "Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"

exts, urls = {}, {}
for line in conf.read_text().splitlines():
    fields = line.split("#", 1)[0].split()
    if not fields:
        continue
    if len(fields) == 2:      # `bundle_id  url_scheme`
        urls[fields[1]] = fields[0]
    elif len(fields) == 3:    # `bundle_id  extension  role`
        exts[fields[1]] = fields[0]

def uti_for(ext):
    fd, path = tempfile.mkstemp(suffix="." + ext)
    os.close(fd)
    try:
        return subprocess.check_output(
            ["mdls", "-name", "kMDItemContentType", "-raw", path],
            text=True,
        ).strip()
    finally:
        os.remove(path)

plist.parent.mkdir(parents=True, exist_ok=True)
data = plistlib.loads(plist.read_bytes()) if plist.exists() else {}
handlers = data.setdefault("LSHandlers", [])

def upsert(match_key, match_val, bundle_id, role_keys):
    entry = next((h for h in handlers if h.get(match_key) == match_val), None)
    if entry is None:
        entry = {match_key: match_val}
        handlers.append(entry)
    for rk in role_keys:
        entry[rk] = bundle_id

for ext, bid in exts.items():
    upsert("LSHandlerContentType", uti_for(ext), bid,
           ["LSHandlerRoleAll", "LSHandlerRoleEditor"])
for scheme, bid in urls.items():
    upsert("LSHandlerURLScheme", scheme, bid, ["LSHandlerRoleAll"])

with open(plist, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
print(f"  patched {len(exts)} extensions and {len(urls)} URL schemes")
PY

# Reload cfprefsd + Launch Services so changes take effect without a relogin
killall cfprefsd 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -seed 2>/dev/null || true

echo ""
echo "Done. Manual steps remaining:"
echo "  - Alfred themes: import from $DOTS/manual/alfred/themes/ via Alfred Preferences → Appearance"
echo "  - Enhancer for YouTube: import $DOTS/manual/enhancer_for_youtube/config.json via extension settings"
echo "  - App Store: Yoink, Klack, Amphetamine, Googly Eyes"
echo "  - Online: ZoomHider, IsThereNet, Coder Desktop"
