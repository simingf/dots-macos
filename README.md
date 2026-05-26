# Mac Setup

## Disable Hold Key For Tilde

```bash
defaults write -g ApplePressAndHoldEnabled -bool false
```

## Remove Dock

```bash
defaults write com.apple.dock autohide-delay -float 1000; killall Dock
```

To revert:

```bash
defaults delete com.apple.dock autohide-delay; killall Dock
```

## git-lfs setup

```bash
git lfs install --system
```

## Dotfiles Setup

```bash
touch ~/.hushlogin
cd ~/dots-macos && stow . --target ~
```

## Homebrew

```bash
brew bundle install --file=~/dots-macos/Brewfile
```

## Manual Setup

- **Alfred themes** — import from `manual/alfred/themes/` via Alfred Preferences → Appearance
- **Alfred terminal custom setup** — paste contents of `manual/alfred/terminal_custom.applescript` into Alfred Preferences → Features → Terminal/Shell → Application: Custom (launches Ghostty)
- **Enhancer for YouTube** — import `manual/enhancer_for_youtube/config.json` via extension settings
- **Iris CE layout** — import `manual/iris_ce/iris_ce_rev__1.layout.json` via VIA configurator (https://caniusevia.com/)

### Paid Casks

- Alcove
- AlDente
- Alfred
- Crossover
- LookAway

## Download Via App Store

### Paid:

Yoink
rcmd (currently not installed)
Klack

### Free:

Amphetamine
Googly Eyes
Xcode (currently not installed)

## Download Online

### Paid:

SideNotes (currently not installed)

### Free:

ZoomHider
IsThereNet
Coder Desktop
Docker Desktop
Google Chrome
Roblox
Roblox Studio
Vencord
Mousecape (currently not installed)
Stacher (currently not installed)

## Roblox / Work Apps

Managed and installed by Roblox IT:

- Falcon
- GlobalProtect
- Jamf Self Service
- Roscan
- Santa

## xclient.info / 52mac.com / macked.app

Cleanshot X (4.7.6, 5/6) (NO LIFETIME LICENSE)

## Alfred Workflows

Amazon Suggest
Arc Tabs and Spaces
Calculate Anything
Google Suggest
System Settings
Thumbnail Navigation
Youtube Suggest
