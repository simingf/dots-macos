# dots-macos

macOS dotfiles. **Source of truth** for two sibling repos:

- [dots-linux](https://github.rbx.com/Roblox/dots-linux) — Coder Linux dev boxes (`*.coder`).
- [dots-windows](https://github.com/simingf/dots-windows) — personal Windows machine.

Operational details (sync workflow, sync contract, editing conventions) live in [`CLAUDE.md`](./CLAUDE.md).

## Bootstrap

```bash
touch ~/.hushlogin
cd ~/dots-macos && stow . --target ~     # symlinks into $HOME
brew bundle install --file=~/dots-macos/Brewfile
```

`scripts/setup.sh` does the full bootstrap (the above plus `rustup`, `cargo install spotify_player`, and [ani-cli](https://github.com/pystardust/ani-cli) — the last not in Homebrew, copied into `$(brew --prefix)/bin`).

## Layout

```
dots-macos/
├── .config/                            # XDG configs (stow → ~/.config/)
│   ├── nvim/                           # init.lua + lazy-lock.json (byte-identical to siblings)
│   ├── aerospace/                      # tiling WM
│   ├── ohmyposh/, ripgrep/, gh/        # byte-identical with dots-windows
│   └── ...
├── Library/
│   ├── Application Support/            # lazygit, VS Code (file-level symlinks)
│   └── Preferences/                    # sapling/ (dir-level symlink)
├── .zshrc, .gitconfig, .tmux.conf      # home dotfiles
├── .finicky.ts                         # Finicky: routes all external links to work Chrome profile
├── .claude/                            # file-level symlinks → ~/.claude/ (runtime state in that dir)
│   ├── CLAUDE.md                       # global Claude Code instructions
│   ├── settings.json                   # Claude Code settings (permissions, model, statusLine)
│   └── statusline-command.sh           # status-line renderer (Oh My Posh zen mirror)
├── scripts/
│   ├── sync-dotfiles.py                # cross-repo orchestration: cp byte-identical files into siblings
│   ├── refresh-linux-vendored.sh       # cross-repo orchestration: rsync vendored plugins into dots-linux
│   ├── setup.sh, check-brew-sync.sh    # Mac-only helpers
│   └── tmux-fzf-*.sh                   # called from .tmux.conf, byte-identical with dots-linux
├── manual/
│   ├── preferences/                    # app plists (cp, not symlink — cfprefsd breaks symlinks)
│   └── ...                             # other configs requiring manual import (not stow-managed)
└── Brewfile
```

## Things you can ask Claude

- **"sync my dotfiles"** — runs `scripts/sync-dotfiles.py --apply` (byte-identical files only).
- **"refresh the Linux vendored plugins"** — runs `nvim --headless +Lazy sync`, `zsh -ic 'zinit update --all'`, then `scripts/refresh-linux-vendored.sh`.
- **"mirror this alias to Linux"** / **"mirror this function to Windows"** — hand-port a `.zshrc` change into `dots-linux/.zshrc` (skipping Mac-only tools) or `dots-windows/Documents/PowerShell/Profile.ps1` (translating zsh→PowerShell).
- **"snapshot `<app>` preferences"** — copies `~/Library/Preferences/<domain>.plist` into `manual/preferences/` and commits.
- **"I installed `<app>`, set it up in my dots"** / **"add `<app>` to dotfiles"** — walks the checklist in [`CLAUDE.md`](./CLAUDE.md#new-tool--app-setup): install path, config placement + stow, sync wiring, sibling-repo updates, docs.

See [`CLAUDE.md`](./CLAUDE.md) for the full sync contract and operational rules.

## Symlink conventions

- **Default**: directory-level symlinks (`.config/<app>/`, `Library/Application Support/<app>/`).
- **`~/Library/Preferences/*.plist`** — **never symlink**. macOS `cfprefsd` atomically replaces plists on write, breaking symlinks and resetting settings. Store in `manual/preferences/` and copy during setup (`scripts/setup.sh`). To snapshot current settings: `cp ~/Library/Preferences/<domain>.plist manual/preferences/`.
- **File-level exceptions** when the target dir holds runtime state:
  - `~/.config/portpal/` — runtime `.sock`; only `portpal.toml` is symlinked.
  - `~/.config/spotify-player/` — runtime token cache; only `app.toml` is symlinked.
  - `~/Library/Application Support/Code/User/` — VS Code state; only `settings.json` + `keybindings.json`.
  - `~/.ssh/` — `coder config-ssh` rewrites `~/.ssh/config` via atomic-rename (breaks symlinks); only `coder-multiplex.conf` is symlinked, included from a real `~/.ssh/config`.
- Always **relative paths** in symlinks — never hardcode `/Users/sfeng/`.
- Don't commit `*.sock`, `*.pid`, `*.lock`.

---

## Fresh Mac setup checklist

Personal reference — run after `stow` + Homebrew above.

### Disable hold-key for tilde

```bash
defaults write -g ApplePressAndHoldEnabled -bool false
```

### Remove dock

```bash
defaults write com.apple.dock autohide-delay -float 1000; killall Dock
# revert: defaults delete com.apple.dock autohide-delay; killall Dock
```

### git-lfs

```bash
git lfs install --system
```

### Set Finicky as default browser

Open `/Applications/Finicky.app` once to accept default-browser (or System Settings → Desktop & Dock → Default web browser). `~/.finicky.ts` is already symlinked and routes every link to the `Default` Chrome profile (work). Edit `profile` if Chrome renumbers folders.

### Manual imports

- **Alfred themes** — import from `manual/alfred/themes/` via Alfred Preferences → Appearance.
- **Alfred terminal custom setup** — paste `manual/alfred/terminal_custom.applescript` into Alfred Preferences → Features → Terminal/Shell → Application: Custom (launches Ghostty).
- **Enhancer for YouTube** — import `manual/enhancer_for_youtube/config.json` via extension settings.
- **Iris CE layout** — import `manual/iris_ce/iris_ce_rev__1.layout.json` via VIA configurator (https://caniusevia.com/).

### Paid casks

Alcove, AlDente, Alfred, AltTab, Crossover, LookAway, Shottr

### App Store

- **Paid**: Yoink, rcmd (not installed), Klack
- **Free**: Amphetamine, Googly Eyes, Xcode (not installed)

### Download online

- **Paid**: SideNotes (not installed)
- **Free**: ZoomHider, IsThereNet, Coder Desktop, Docker Desktop, Google Chrome, Roblox, Roblox Studio, Vencord, Mousecape (not installed), Stacher (not installed)

### Roblox / work apps

Managed and installed by Roblox IT: Falcon, GlobalProtect, Jamf Self Service, Roscan, Santa.

### xclient.info / 52mac.com / macked.app

Cleanshot X (4.7.6, 5/6) — no lifetime license.

### Alfred workflows

Amazon Suggest, Arc Tabs and Spaces, Calculate Anything, Google Suggest, System Settings, Thumbnail Navigation, Youtube Suggest.
