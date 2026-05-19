# dots — Claude Instructions

## Repo structure

```
dots/
├── .config/          # XDG config dirs (stow → ~/.config/)
├── Library/
│   ├── Application Support/   # e.g. lazygit, VS Code
│   └── Preferences/           # e.g. sapling
├── manual/           # configs requiring manual import (Alfred, Enhancer for YouTube, Iris CE) — NOT stow-managed
├── scripts/          # setup.sh, check-brew-sync.sh
└── Brewfile          # Homebrew packages
```

Apply all symlinks with:

```bash
cd ~/dots && stow . --target ~
```

## Symlink conventions

### Directory-level symlinks (default)

Symlink the whole app directory. Applies to `.config/` subdirs and `Library/` subdirs:

```
~/.config/nvim                        →  ../dots/.config/nvim
~/Library/Application Support/lazygit →  ../../dots/Library/Application Support/lazygit
~/Library/Preferences/sapling         →  ../../dots/Library/Preferences/sapling
```

When adding a new app config, put its directory in the right place under `dots/` and stow creates the directory-level symlink automatically.

### File-level symlinks (exceptions)

Use when the target directory contains runtime files that must not be committed (sockets, caches, generated state). Keep the real directory in place and symlink only the config files inside it.

Current exceptions:
- `~/.config/portpal/` — has a `.sock` at runtime; only `portpal.toml` is symlinked
- `~/Library/Application Support/Code/User/` — VS Code runtime state; only `settings.json` and `keybindings.json` are symlinked
- `~/.ssh/` — contains `known_hosts`, `cm-*` ControlMaster sockets, private keys; **and** `~/.ssh/config` itself is rewritten by `coder config-ssh` via atomic-rename (which breaks symlinks). So `~/.ssh/config` stays as a real file; only `~/.ssh/coder-multiplex.conf` is symlinked, included from `~/.ssh/config` via an `Include` directive placed outside Coder's managed markers

### Home dotfiles

Single files in `~` are necessarily file-level:

```
~/.zshrc     →  dots/.zshrc
~/.gitconfig →  dots/.gitconfig
```

### Symlink path style

Always use **relative paths**. Never hardcode `/Users/sfeng/`.

### What not to commit

Do not commit runtime artifacts: `*.sock`, `*.pid`, `*.lock`. Add to `.gitignore` if they appear under a tracked path.
