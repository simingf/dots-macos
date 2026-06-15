# Fix setup.sh for fresh-machine reliability

## Context

Running `./setup.sh` on a fresh Mac fails at multiple points because:
1. `stow` is used on line 60 but isn't installed until `brew bundle` on line 69
2. Cask installs prompt for the user's password repeatedly (each cask that needs `/Applications` access triggers its own `sudo` prompt)
3. The `set -euo pipefail` at the top causes the script to exit on any command-not-found, forcing the user to reopen a terminal and re-run

## Changes to `scripts/setup.sh`

### 1. Install stow before using it

Add `brew install stow 2>/dev/null` between the Homebrew setup (line 18) and the "Dotfiles (stow)" step (line 30). This ensures stow is available when first needed. `brew bundle` later is a no-op for already-installed formulae.

### 2. Sudo keepalive for cask installs

Add a sudo keepalive block near the top (after brew setup). Standard pattern:
```bash
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
```

This acquires sudo once and refreshes the ticket every 60s so cask installs never re-prompt.

### 3. PATH refresh after brew bundle

After `brew bundle install` completes, re-eval `brew shellenv` to pick up any new PATH entries (e.g., if brew itself was upgraded or keg-only formulae linked). The cargo fix we already applied handles the rustup case. No other commands in the script are used before they're installed (git-lfs, rustup, python3 are all used after brew bundle).

## Verification

- Read through the final script and confirm every command is available at the point it's called
- `bash -n scripts/setup.sh` for syntax check
