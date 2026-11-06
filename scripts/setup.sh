#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$DOTS/Brewfile" ] || { echo "Error: DOTS=$DOTS doesn't look like dots-macos" >&2; exit 1; }

step() { echo "==> $*"; }

step "Install Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# brew on PATH even right after a fresh install
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

step "Sudo keepalive (for cask installs)"
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
# brew runs `sudo --reset-timestamp` per process (re-prompting per cask) unless this
# internal var says sudo was already checked.
export HOMEBREW_SUDO_CHECKED=1

# stow runs before brew bundle
brew install stow 2>/dev/null || true

step "Disable press-and-hold (tilde key)"
defaults write -g ApplePressAndHoldEnabled -bool false

step "Dock preferences"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000
defaults write com.apple.dock orientation -string left
defaults write com.apple.dock show-recents -bool false

step "Window tiling (off — managed by aerospace)"
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
defaults write com.apple.WindowManager EnableTilingOptionAccelerator -bool false
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false
defaults write com.apple.WindowManager EnableTopTilingByDrag -bool false

step "Mission Control (aerospace compatibility)"
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock expose-group-apps -bool true
defaults write -g AppleSpacesSwitchOnActivate -bool false
defaults write com.apple.spaces spans-displays -bool true

killall Dock 2>/dev/null || true

step "Suppress login banner"
touch ~/.hushlogin

step "Dotfiles (stow)"
# stow won't overwrite real files: remove conflicting ones in $HOME (assumed fresh-box
# defaults). Keep the excludes in sync with .stow-local-ignore.
find "$DOTS" -type f \
    -not -path "$DOTS/.git/*" \
    -not -path "$DOTS/scripts/*" \
    -not -path "$DOTS/manual/*" \
    -not -path "$DOTS/ssh-dots/*" \
    -not -path "$DOTS/learnings/*" \
    -not -path "$DOTS/archive/*" \
    -not -name '.DS_Store' \
    -not -name '.gitignore' \
    -not -name 'Brewfile' \
    -not -name 'README.md' \
    -not -name 'KEYBINDS.md' \
    -not -name 'THEME.md' \
    -not -name 'CLAUDE.md' \
| while IFS= read -r f; do
  target="$HOME/${f#$DOTS/}"
  [ -e "$target" ] || continue
  # Already ours? (-L on the leaf misses stow's tree-folded parent dirs)
  real=$(realpath "$target" 2>/dev/null || true)
  case "$real" in "$DOTS"/*) continue;; esac
  echo "  rm $target"
  rm -f "$target"
done

# Pre-create dirs that hold runtime state (OAuth tokens) so stow links files, not the dir
mkdir -p "$HOME/.config/spotify-player"

step "Docker Artifactory config"
mkdir -p "$HOME/.docker"
if [ ! -f "$HOME/.docker/config.json" ]; then
  cat > "$HOME/.docker/config.json" <<'DJSON'
{
    "auths": {
        "https://docker.artifactory.rbx.com": {
            "auth": "REPLACE_WITH_base64(username:identity-token)",
            "email": "sfeng@roblox.com"
        }
    }
}
DJSON
  echo "  ⚠ Created ~/.docker/config.json with placeholder — run: docker login docker.artifactory.rbx.com"
fi

stow --dir="$DOTS" --target="$HOME" .

# ~/.claude is runtime state, so it's stow-ignored: real dir + file-level relative links
# (mirrors dots-linux/setup.sh; BSD ln has no -r).
mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/themes"
for f in CLAUDE.md settings.json statusline-command.sh \
         hooks/agent-notify.sh hooks/agent-status.sh hooks/agent-clip.py themes/rose-pine.json; do
  rel=$(/usr/bin/python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
        "$DOTS/.claude/$f" "$(dirname "$HOME/.claude/$f")")
  ln -sfn "$rel" "$HOME/.claude/$f"
done

step "Homebrew bundle"
# brew refuses formulae from untrusted taps; skip already-present taps (slow fetch)
tapped=$(brew tap)
sed -n 's/^tap "\([^"]*\)".*/\1/p' "$DOTS/Brewfile" | while IFS= read -r tap; do
  echo "$tapped" | grep -qx "$tap" && continue
  brew tap "$tap" 2>/dev/null || true
  brew trust "$tap" 2>/dev/null || true
done
brew bundle install --file="$DOTS/Brewfile"
brew bundle cleanup --force --file="$DOTS/Brewfile"
eval "$(brew shellenv)"

step "git-lfs install"
git lfs install

step "Git push PAT (login keychain)"
# gh's token 403s on git-write, so .gitconfig uses osxkeychain: seed a classic 'repo'
# PAT per (host, username) once. sfeng-roblox serves github.com/Roblox/* (includeIf).
have_pat() {   # host user — this account's PAT already in keychain?
  printf 'protocol=https\nhost=%s\nusername=%s\n' "$1" "$2" | git credential-osxkeychain get 2>/dev/null | grep -q '^password='
}
store_pat() {  # host user token
  printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n' "$1" "$2" "$3" | git credential-osxkeychain store
}
seed_pat() {   # host user
  if have_pat "$1" "$2"; then echo "  $1 ($2) already in keychain ✓"; return; fi
  if [ ! -t 0 ]; then echo "  ⚠ no PAT for $1 ($2) — run setup.sh interactively to be prompted"; return; fi
  printf '  PAT for %s (account %s, classic repo scope, blank to skip): ' "$1" "$2"
  local tok; read -rs tok; echo
  [ -n "$tok" ] || { echo "    skipped $1 ($2)"; return; }
  store_pat "$1" "$2" "$tok"
  unset tok
  echo "  $1 ($2) stored ✓"
}
seed_pat github.com     simingf
seed_pat github.com     sfeng-roblox
seed_pat github.rbx.com sfeng

step "gh API token (heal from keychain PAT)"
# Only if `gh auth status` fails: log gh in with the keychain PAT (needs classic
# repo + read:org). GH_*TOKEN are unset since they mask the stored token and make
# `gh auth login` refuse. gh has one account per host → Roblox one on github.com.
heal_gh() {    # host user
  local ghenv=(env -u GH_TOKEN -u GH_ENTERPRISE_TOKEN)
  if "${ghenv[@]}" gh auth status -h "$1" >/dev/null 2>&1; then echo "  gh $1 ✓"; return; fi
  local pat
  pat=$(printf 'protocol=https\nhost=%s\nusername=%s\n' "$1" "$2" | git credential-osxkeychain get 2>/dev/null | sed -n 's/^password=//p' || true)
  [ -n "$pat" ] || { echo "  ⚠ gh $1: no keychain PAT for $2 — run: gh auth login -h $1"; return; }
  if printf '%s\n' "$pat" | "${ghenv[@]}" gh auth login -h "$1" --with-token 2>/dev/null; then
    echo "  gh $1 ($2): healed from keychain PAT ✓"
  else
    echo "  ⚠ gh $1: keychain PAT for $2 rejected (needs classic repo + read:org) — run: gh auth login -h $1"
  fi
  unset pat
}
heal_gh github.com     sfeng-roblox
heal_gh github.rbx.com sfeng

step "Rust toolchain (rustup)"
rustup default stable
# Homebrew's rustup makes no ~/.cargo/bin proxies
export PATH="$(rustup which cargo | xargs dirname):$PATH"

step "cargo-update (cargo) — lets topgrade upgrade cargo-installed bins"
command -v cargo-install-update >/dev/null 2>&1 || \
  cargo install cargo-update --locked 2>&1 | grep -v "be sure to add"

step "spotify_player (cargo)"
command -v spotify_player >/dev/null 2>&1 || \
  cargo install spotify_player --features image,notify --locked 2>&1 | grep -v "be sure to add"

step "ani-cli (not in Homebrew)"
if ! command -v ani-cli >/dev/null 2>&1; then
  anicli_tmp=$(mktemp -d)
  trap '/bin/rm -rf "$anicli_tmp"' EXIT
  git clone --depth=1 https://github.com/pystardust/ani-cli.git "$anicli_tmp/ani-cli"
  install -m 0755 "$anicli_tmp/ani-cli/ani-cli" "$(brew --prefix)/bin/ani-cli"
fi

step "mermaid-cli (npm — snacks.image mermaid diagram rendering in nvim)"
if command -v npm >/dev/null 2>&1 && ! command -v mmdc >/dev/null 2>&1; then
  npm install -g @mermaid-js/mermaid-cli
fi

step "Default file handlers (Launch Services plist)"
# Patch the LaunchServices plist directly instead of running `duti`:
# - duti writes only RoleEditor; macOS checks RoleAll first, so a RoleAll app (Cursor) wins.
# - extensions without a public UTI get a dyn.* one, and duti guesses the wrong one;
#   probe the real UTI with `mdls` on a temp file instead.
# Unfixable: Cursor claims .json with LSHandlerRank Owner, which beats user prefs.
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

# Reload so it applies without a relogin
killall cfprefsd 2>/dev/null || true
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -seed >/dev/null 2>&1
fi

step "Ghostty terminfo (xterm-ghostty)"
# Else TERM=xterm-ghostty in tmux panes breaks ncurses/clear and zsh double-echoes
ghostty_ti="/Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty"
if [ -f "$ghostty_ti" ]; then
  mkdir -p "$HOME/.terminfo/78"
  cp "$ghostty_ti" "$HOME/.terminfo/78/xterm-ghostty"
fi

step "kitten on PATH (for icat image previews)"
# `kitten` lives in kitty.app; the `icat` alias uses it under ghostty (kitty graphics protocol)
kitten_bin="/Applications/kitty.app/Contents/MacOS/kitten"
if [ -x "$kitten_bin" ]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$kitten_bin" "$HOME/.local/bin/kitten"
fi

step "Alfred sync folder"
alfred_prefs="$HOME/Library/Application Support/Alfred/prefs.json"
mkdir -p "$(dirname "$alfred_prefs")"
cat > "$alfred_prefs" <<AJSON
{
  "current" : "$DOTS/.config/alfred/Alfred.alfredpreferences",
  "localhash" : ""
}
AJSON

step "App preferences (defaults import)"
for plist in "$DOTS"/manual/preferences/*.plist; do
  [ -f "$plist" ] || continue
  domain=$(basename "$plist" .plist)
  echo "  $domain"
  cp "$plist" "$HOME/Library/Preferences/$(basename "$plist")"
done
killall cfprefsd 2>/dev/null || true

cat <<EOF

Done. Manual steps remaining:
  - Finicky: set as default browser in System Settings → Desktop & Dock → Default web browser
  - Alfred: relaunch Alfred so it picks up the sync folder (preferences/themes/snippets/workflows auto-load)
  - Enhancer for YouTube: import $DOTS/manual/enhancer_for_youtube/config.json via extension settings
  - App Store: Klack, Googly Eyes
  - Online: ZoomHider
  - Re-launch AlDente and AltTab to pick up imported preferences
EOF
