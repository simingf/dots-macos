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
│   ├── borders/                        # window border highlights
│   ├── btop/                           # system monitor
│   ├── finicky/                        # routes all external links to work Chrome profile
│   ├── ghostty/                        # terminal emulator
│   ├── istherenet/                     # network status menubar
│   ├── linearmouse/                    # mouse acceleration/scrolling
│   ├── ohmyposh/, ripgrep/, gh/        # byte-identical with dots-windows
│   ├── spotify-player/                 # app.toml, keymap.toml, theme.toml
│   ├── yazi/                           # file manager (byte-identical with dots-linux)
│   └── topgrade.toml, karabiner/, kitty/
├── Library/
│   ├── Application Support/            # lazygit, VS Code (file-level symlinks)
│   └── Preferences/                    # sapling/ (dir-level symlink)
├── .zshrc, .gitconfig, .tmux.conf      # home dotfiles
├── .claude/                            # file-level symlinks → ~/.claude/ (runtime state in that dir)
│   ├── CLAUDE.md                       # global Claude Code instructions
│   ├── settings.json                   # Claude Code settings (permissions, model, statusLine)
│   └── statusline-command.sh           # status-line renderer (Oh My Posh zen mirror)
├── scripts/
│   ├── sync-dotfiles.py                # cross-repo orchestration: cp byte-identical files into siblings
│   ├── refresh-linux-vendored.sh       # cross-repo orchestration: rsync vendored plugins into dots-linux
│   ├── setup.sh                        # full bootstrap (brew, rustup, cargo install, ani-cli, plists)
│   ├── check-brew-sync.sh, sync-brew.sh  # Brewfile drift helpers
│   ├── duti.conf                       # default app associations (used by setup.sh)
│   ├── iina-cli-activate.sh            # open IINA via /usr/bin/open for tmux GUI compat
│   ├── tag-casks-orange.sh             # Finder tag paid casks for visibility
│   └── tmux-fzf-*.sh                   # called from .tmux.conf, byte-identical with dots-linux
├── manual/
│   ├── alfred/                         # Alfred sync folder (preferences, themes, snippets, workflows)
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
  - `~/.config/spotify-player/` — runtime token/cache files; only `app.toml`, `keymap.toml`, `theme.toml` are tracked.
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

Open `/Applications/Finicky.app` once to accept default-browser (or System Settings → Desktop & Dock → Default web browser). `~/.config/finicky/finicky.ts` is already symlinked and routes every link to the `Default` Chrome profile (work). Edit `profile` if Chrome renumbers folders.

### Paid casks

Alcove, AlDente, Alfred, AltTab, BetterTouchTool, Clop, LookAway, Shottr, Yoink

### App Store

- **Paid**: Klack
- **Free**: Googly Eyes, Xcode (not installed)

### Casks (not installed)

- **Paid**: rcmd, SideNotes

### Download online

- **Free**: ZoomHider, Mousecape (not installed), Stacher (not installed)

### Jamf (Roblox IT)

Managed via Jamf Self Service or auto-installed by Roblox IT:

- **Self Service**: Google Chrome, Docker Desktop, VS Code, Zoom, JetBrains Rider, Roblox Player, Roblox Studio
- **Auto-managed**: Falcon, GlobalProtect, Jamf Self Service, Roscan, Santa

### xclient.info / 52mac.com / macked.app

Cleanshot X (4.7.6, 5/6) — no lifetime license.

### Manual imports

- **Alfred** — `setup.sh` seeds `prefs.json` so Alfred loads from `manual/alfred/` on first launch. On an existing machine: Alfred Preferences → Advanced → "Set preferences folder…" → `~/dots-macos/manual/alfred`.
- **Enhancer for YouTube** — import `manual/enhancer_for_youtube/config.json` via extension settings.
- **Iris CE layout** — import `manual/iris_ce/iris_ce_rev__1.layout.json` via VIA configurator (https://caniusevia.com/).
