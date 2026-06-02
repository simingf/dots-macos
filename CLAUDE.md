# dots-macos — Claude Instructions

`~/dots-macos` is the **source of truth** for all three dotfile repos:

- `~/dots-linux` — public on github.rbx.com; Coder applies on Linux dev boxes (`*.coder`). No internet on the box, so plugins/terminfo are vendored.
- `~/dots-windows` — personal Windows. **Must contain no work content.**

For repo layout and bootstrap, see [`README.md`](./README.md).

## Behavior

When the user asks you to edit a file, route by sync class (see contract below):

- **Byte-identical** with a sibling: edit here (Mac is source), then run `scripts/sync-dotfiles.py --apply` in the same task. Idempotent.
- **Partial** (e.g., `.zshrc`, `.gitconfig`): edit here, then judge whether to hand-mirror. Generic changes (new alias/function) propagate to siblings, **translating Mac-only tools out** (`eza`, `trash`, `pbcopy`, oh-my-posh, homebrew, `/Applications/`). Platform-specific changes don't. Ask if unsure.
- **Mac-only**: edit and you're done.

Don't end a task that touched a byte-identical file without running the sync script.

## New tool / app setup

When the user says **"I installed `<app>`"** / **"set up `<app>` in my dots"** / **"add `<app>` to dotfiles"**, walk this checklist. Say "N/A: `<reason>`" rather than skipping silently. End by `ls -la`-ing the symlink and (if shared) running `scripts/sync-dotfiles.py` to confirm in-sync.

1. **Install path** — record how it gets onto a fresh machine:
   - Homebrew formula/cask → `Brewfile` (alphabetical).
   - App Store / paid / manual download / Roblox-IT → matching subsection of README "Fresh Mac setup checklist".
   - Bootstrap beyond `brew bundle` (`rustup`, `cargo install`, copy a binary into `$(brew --prefix)/bin`, etc.) → `scripts/setup.sh`.
2. **Config placement** — pick the canonical path inside `~/dots-macos/`: `.config/<app>/` (XDG, preferred), `Library/Application Support/<app>/` (macOS-only apps), `.<app>rc` / `.<app>` (home-level dotfile), or `manual/preferences/<domain>.plist` (macOS plist — **never stow**, see Editing conventions).
3. **Stow** — from `~/dots-macos` run `stow . --target ~`. Default to directory-level symlinks; switch to file-level when the dir holds runtime state (see README "Symlink conventions"). For plists: skip stow, the file lives under `manual/` and is copied by `scripts/setup.sh`.
4. **Sync class** — pick a row in the contract below:
   - byte-identical → add to `IDENTICAL["linux"]` / `IDENTICAL["windows"]` in `scripts/sync-dotfiles.py`, then `--apply` to seed.
   - partial → hand-mirror generic parts to siblings.
   - Mac-only → no mirror.
5. **Siblings** — if linux/windows got a copy:
   - `dots-linux`: strip Mac-only tools; vendor binaries/plugins under `dots-linux/vendor/` (no internet on dev box); update `dots-linux/setup.sh` if bootstrap differs.
   - `dots-windows`: hand-translate (zsh→PowerShell, paths→`AppData/`); no work content.
6. **Docs**:
   - This CLAUDE.md sync contract: add a row.
   - This README Layout: add an entry. If manual post-install (set as default app, import a config, paste a license), add to "Fresh Mac setup checklist".
   - Sibling READMEs: update Layout if they got a copy.
   - Sibling CLAUDE.mds: only if the tool introduces editing conventions for that platform (runtime guards, line endings, gotchas) or new partials worth referencing. The sync contract is canonical here — don't duplicate.
   - "Things you can ask Claude": only if a new user-facing phrasing is worth memorizing.

## Sync workflow

```bash
~/dots-macos/scripts/sync-dotfiles.py            # dry-run, shows drift
~/dots-macos/scripts/sync-dotfiles.py --apply    # copy drifted files
```

When the user says **"refresh Linux vendored plugins"**:

```bash
nvim --headless +"Lazy! sync" +qa
zsh -ic 'zinit update --all'
~/dots-macos/scripts/refresh-linux-vendored.sh
~/dots-macos/scripts/sync-dotfiles.py --apply linux   # in case init.lua/.tmux.conf drifted
```

User commits/pushes from each sibling repo themselves.

## Sync contract

| File / dir | linux | windows | Rule |
|---|---|---|---|
| `.tmux.conf` | byte-identical | — | Inline portability via `if-shell 'test "$(uname)" = Linux' ...`; path differences use `$DOTFILES_DIR/scripts/...` exported per-host from `.zshrc`. |
| `.config/nvim/init.lua` | byte-identical | byte-identical | Runtime guards `IS_SSH` (Linux dev box) and `HAS_DOTNET` (work Mac only) gate Mason/blink-Rust/roslyn. |
| `.config/nvim/lazy-lock.json` | byte-identical | byte-identical | |
| `scripts/tmux-fzf-*.sh` | byte-identical | — | Called from `.tmux.conf` via `$DOTFILES_DIR`. |
| `.config/yazi/{yazi,keymap,theme}.toml` + `flavors/rose-pine.yazi/{flavor.toml,tmtheme.xml}` | byte-identical | — | Linux `yazi`+`ya` binaries vendored under `dots-linux/vendor/bin/`. New yazi files must be added to `IDENTICAL["linux"]` in `sync-dotfiles.py`. |
| `Library/Application Support/lazygit/config.yml` | — | byte-identical | |
| `Library/Application Support/Code/User/{settings,keybindings}.json` | — | byte-identical | LF line endings (Mac normalized). |
| `.config/{ohmyposh/zen.toml, ripgrep/rg.conf, gh/config.yml}` | — | byte-identical | |
| `.zshrc` | partial | — | Linux uses its own prompt (`vcs_info` vs oh-my-posh), plugin loader (vendored vs zinit), `ls`/`grep`/`rm` aliases (no `eza`/`trash`), `pbcopy` stub, devspace env vars, `kk`/`kkr` → `claude` (vs `declawd`). Hand-mirror new shared aliases. |
| `.gitconfig` | partial | — | Linux is minimal: `user.name` + `github.rbx.com` credential helper. Mac has personal+work GH accounts, LFS, GCM, maintenance. |
| `.claude/CLAUDE.md` | byte-identical | byte-identical | Global Claude Code instructions. Platform-agnostic. |
| `Documents/PowerShell/Profile.ps1` (in dots-windows) | — | partial | Hand-translated subset of `.zshrc`. |
| `.bashrc`, `vendor/`, `setup.sh` | Linux-only | — | |
| `AppData/Local/Packages/Microsoft.WindowsTerminal_…/`, `scripts/apply.ps1` | — | Windows-only | |
| `.finicky.ts` | — | — | Mac-only. Routes every external link to the `Default` Chrome profile (work). |
| `Library/` (rest), `Brewfile`, `manual/`, `ghostty/`, `kitty/`, `aerospace/`, `karabiner/` | Mac-only | Mac-only | Do NOT mirror. |

## Scripts policy

- **Bootstrap** lives in its own repo (`dots-macos/scripts/setup.sh`, `dots-linux/setup.sh`, `dots-windows/scripts/apply.ps1`) — each runs on the platform it applies.
- **Cross-repo orchestration** lives in `dots-macos/scripts/` (`sync-dotfiles.py`, `refresh-linux-vendored.sh`) since Mac is the control plane.
- **Config helpers** (`scripts/tmux-fzf-*.sh`) live in every repo where the calling config runs, synced byte-identical.

## Editing conventions

- `init.lua` runtime guards: `local IS_SSH = (vim.env.SSH_CONNECTION or "") ~= ""` and `local HAS_DOTNET = vim.fn.executable("dotnet") == 1`. Gate Mason / Rust-fuzzy / roslyn — don't introduce host-specific files.
- `.tmux.conf` portability: `if-shell 'test "$(uname)" = Linux' '<linux-cmd>' '<mac-cmd>'`. Path differences via `$DOTFILES_DIR` exported from `.zshrc`.
- VS Code JSON files: LF only.
- Symlinks: relative paths only — never hardcode `/Users/sfeng/`.
- **Plists: never symlink.** macOS `cfprefsd` atomically replaces plist files, breaking symlinks. Store app plists in `manual/preferences/` and restore via `cp` in `scripts/setup.sh`. To snapshot: `cp ~/Library/Preferences/<domain>.plist manual/preferences/`.
- **macOS GUI apps launched from tmux:** processes spawned from a tmux pane inherit a non-GUI audit session, so direct-exec launches of `.app` binaries (or CLIs that exec them — e.g. `iina-cli`) draw windows but never register with NSWorkspace — no menu bar, no cmd-tab, no activation. Wrap in `/usr/bin/open -na <App> --args <flags> <file/url>`. Pattern: `scripts/iina-cli-activate.sh` (set as `ANI_CLI_PLAYER` in `.zshrc`). `reattach-to-user-namespace` does **not** fix this — different issue (bootstrap port, not audit session).

## Doc structure (keep aligned across all 3 repos)

Each repo has `README.md` (human-facing) and `CLAUDE.md` (AI-operational):

| `README.md` | `CLAUDE.md` |
|---|---|
| Repo summary + sibling cross-refs, bootstrap, layout, "Things you can ask Claude", concepts, repo-specific extras | Source-of-truth pointer, **Behavior** (routing rules), sync workflow, sync contract (canonical only here), constraints, editing conventions |

- **Sync contract** is canonical only in this CLAUDE.md. Siblings reference it.
- **Layout** lives in README only. CLAUDE.md may name files when they have operational rules attached, but doesn't repeat the tree.
- **"Things you can ask Claude"** lives in README; each phrasing maps to an operation in CLAUDE.md.
- When changing the sync workflow, propagate to siblings' CLAUDE.mds and "Things you can ask Claude" in all 3 READMEs.
- When changing constraints or editing conventions, update CLAUDE.md only (operational, not user-facing).
