# dots-macos — Claude Instructions

## Repo structure

```
dots-macos/
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
cd ~/dots-macos && stow . --target ~
```

## Symlink conventions

### Directory-level symlinks (default)

Symlink the whole app directory. Applies to `.config/` subdirs and `Library/` subdirs:

```
~/.config/nvim                        →  ../dots-macos/.config/nvim
~/Library/Application Support/lazygit →  ../../dots-macos/Library/Application Support/lazygit
~/Library/Preferences/sapling         →  ../../dots-macos/Library/Preferences/sapling
```

When adding a new app config, put its directory in the right place under `dots-macos/` and stow creates the directory-level symlink automatically.

### File-level symlinks (exceptions)

Use when the target directory contains runtime files that must not be committed (sockets, caches, generated state). Keep the real directory in place and symlink only the config files inside it.

Current exceptions:
- `~/.config/portpal/` — has a `.sock` at runtime; only `portpal.toml` is symlinked
- `~/Library/Application Support/Code/User/` — VS Code runtime state; only `settings.json` and `keybindings.json` are symlinked
- `~/.ssh/` — contains `known_hosts`, `cm-*` ControlMaster sockets, private keys; **and** `~/.ssh/config` itself is rewritten by `coder config-ssh` via atomic-rename (which breaks symlinks). So `~/.ssh/config` stays as a real file; only `~/.ssh/coder-multiplex.conf` is symlinked, included from `~/.ssh/config` via an `Include` directive placed outside Coder's managed markers

### Home dotfiles

Single files in `~` are necessarily file-level:

```
~/.zshrc     →  dots-macos/.zshrc
~/.gitconfig →  dots-macos/.gitconfig
```

### Symlink path style

Always use **relative paths**. Never hardcode `/Users/sfeng/`.

### What not to commit

Do not commit runtime artifacts: `*.sock`, `*.pid`, `*.lock`. Add to `.gitignore` if they appear under a tracked path.

## Linux dev box mirror (`~/dots-linux`)

A separate, public-on-github.rbx.com repo (`~/dots-linux`) holds dotfiles for Coder Linux dev boxes (`*.coder` workspaces). Coder clones it at workspace startup and runs its `setup.sh`. **`~/dots-macos` is the source of truth** for everything shared; dots-linux mirrors a subset, plus vendored plugins/binaries because the dev box has no internet.

See `~/dots-linux/CLAUDE.md` for vendoring, IS_SSH guards, and refresh procedures.

### Sync contract

| File / dir | Sync state | Rule |
|---|---|---|
| `.tmux.conf` | **byte-identical** | One file lives in both repos; portability handled inside via `if-shell 'test "$(uname)" = Linux' ...`. Edit both copies in lockstep. |
| `.config/nvim/init.lua` | **byte-identical** | IS_SSH guards (`vim.env.SSH_CONNECTION`) handle Linux differences inline. Refresh dots-linux with plain `cp`. |
| `.config/nvim/lazy-lock.json` | **byte-identical** | Plain `cp`. |
| `.zshrc` | **partial** | Mac is canonical for shared aliases/functions. Linux has its own prompt (`vcs_info` vs oh-my-posh), plugin loader (vendored vs zinit), and ls/grep/rm aliases (no `eza`/`trash`). When adding a new shared alias/function on Mac, mirror it into the Linux `.zshrc` by hand. |
| `.gitconfig` | **partial** | Linux has only `user.name` + the `github.rbx.com` credential helper using `/usr/bin/gh`. Mac additionally has personal+work GH accounts, LFS, GCM, maintenance — not relevant on the dev box. |
| `.bashrc` | **Linux-only** | 5-line stub that `exec zsh`s. Not in `~/dots-macos`. |
| `vendor/`, `setup.sh` | **Linux-only** | Vendored plugins, terminfo, and the bootstrap script — only relevant on the no-internet dev box. |
| `scripts/tmux-fzf-*.sh` | **byte-identical** | Referenced by `.tmux.conf` via `$DOTFILES_DIR/scripts/...` (exported per-host from `.zshrc`). When edited on Mac, `cp` to `~/dots-linux/scripts/`. Other `scripts/` (brew, setup, duti) stay Mac-only. |
| `Library/`, `Brewfile`, `manual/`, ghostty/kitty/aerospace/ohmyposh/karabiner configs | **Mac-only** | Do NOT mirror to dots-linux. |

### When making changes

- **Editing `.tmux.conf` / `init.lua` / `lazy-lock.json`**: update `~/dots-macos` first, then `cp` to `~/dots-linux/...` to keep them byte-identical.
- **Adding a Mac-only alias/function to `.zshrc`**: decide whether it should also exist on Linux. If yes, mirror it into `~/dots-linux/.zshrc` (skipping pieces that depend on Mac-only tools). If no, leave Linux untouched.
- **Adding a new shared dotfile**: add to `~/dots-macos`, decide if it belongs on Linux too, and if so add a parallel copy and a row to the table above.
