# dots-macos — Claude Instructions

`~/dots-macos` is the **source of truth** for all three dotfile repos:

- `~/dots-linux` — public on github.rbx.com; Coder applies on Linux dev boxes (`*.coder`). No internet on the box, so plugins/terminfo are vendored.
- `~/dots-windows` — personal Windows. **Must contain no work content.**

For repo layout and bootstrap, see [`README.md`](./README.md).

## Behavior

When the user asks you to edit a file, route based on its sync class (see contract below):

- **Byte-identical** with a sibling: edit here (Mac is source), then run `scripts/sync-dotfiles.py --apply` as part of the same task — don't wait for the user to ask. The script is idempotent.
- **Partial** (e.g., `.zshrc`, `.gitconfig`): edit here, then judge whether the change should hand-mirror to the sibling. If the change is generic (a new alias, a new function), propagate to `~/dots-linux` and/or `~/dots-windows` — translating out Mac-only tools (`eza`, `trash`, `pbcopy`, oh-my-posh, homebrew, `/Applications/`). If platform-specific, leave siblings alone. Ask if unsure.
- **Mac-only**: edit and you're done.

Default: the user expects shared files to stay synced. Don't end a task that touched a byte-identical file without running the sync script.

## Sync workflow

When the user says **"sync dotfiles"** (or after editing any byte-identical file below):

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

The user commits/pushes from each sibling repo themselves.

## Sync contract

| File / dir | linux | windows | Rule |
|---|---|---|---|
| `.tmux.conf` | byte-identical | — | Inline portability via `if-shell 'test "$(uname)" = Linux' ...`; path differences use `$DOTFILES_DIR/scripts/...` exported per-host from `.zshrc`. |
| `.config/nvim/init.lua` | byte-identical | byte-identical | Runtime guards `IS_SSH` (Linux dev box) and `HAS_DOTNET` (work Mac only) gate Mason/blink-Rust/roslyn. |
| `.config/nvim/lazy-lock.json` | byte-identical | byte-identical | |
| `scripts/tmux-fzf-*.sh` | byte-identical | — | Called from `.tmux.conf` via `$DOTFILES_DIR`. |
| `Library/Application Support/lazygit/config.yml` | — | byte-identical | |
| `Library/Application Support/Code/User/{settings,keybindings}.json` | — | byte-identical | LF line endings (Mac normalized). |
| `.config/{ohmyposh/zen.toml, ripgrep/rg.conf, gh/config.yml}` | — | byte-identical | |
| `.zshrc` | partial | — | Linux uses its own prompt (`vcs_info` vs oh-my-posh), plugin loader (vendored vs zinit), `ls`/`grep`/`rm` aliases (no `eza`/`trash`), `pbcopy` stub, devspace env vars, and `kk`/`kkr` → `claude` instead of `declawd`. Hand-mirror new shared aliases. |
| `.gitconfig` | partial | — | Linux is minimal: `user.name` + the `github.rbx.com` credential helper. Mac has personal+work GH accounts, LFS, GCM, maintenance. |
| `.claude/CLAUDE.md` | — | partial | Roblox-specific bits (Sapling, Silencer, github.rbx.com paths) live only on Mac; Windows uses `Set-Clipboard` instead of `pbcopy` and drops the Roblox role line. |
| `powershell/profile.ps1` (in dots-windows) | — | partial | Hand-translated subset of `.zshrc`. Mirror new shared shell logic by hand, skipping Mac-only tools. |
| `.bashrc`, `vendor/`, `setup.sh` | Linux-only | — | |
| `windowsterminal/`, `scripts/apply.ps1` | — | Windows-only | |
| `Library/` (rest), `Brewfile`, `manual/`, `ghostty/`, `kitty/`, `aerospace/`, `karabiner/` | Mac-only | Mac-only | Do NOT mirror. |

When extending: add a row above, add to `IDENTICAL` in `sync-dotfiles.py` if byte-identical, update the matching `README.md` layout/things-to-ask sections.

## Scripts policy

Scripts are organized by who runs them:

- **Bootstrap scripts** live in their own repo: `dots-macos/scripts/setup.sh`, `dots-linux/setup.sh`, `dots-windows/scripts/apply.ps1`. Each runs on the platform whose dotfiles it applies.
- **Cross-repo orchestration** lives in `dots-macos/scripts/` because Mac is the control plane: `sync-dotfiles.py`, `refresh-linux-vendored.sh`. They read from `~/dots-macos` and write into the sibling repos.
- **Config helpers** live in every repo where the calling config runs: `scripts/tmux-fzf-*.sh` exists in both dots-macos and dots-linux because tmux runs on both. Synced byte-identical via `sync-dotfiles.py`.

When adding a new script, place it by this rule. Don't copy orchestration scripts into siblings — `~/dots-macos/scripts/sync-dotfiles.py` is invoked from any directory.

## Editing conventions

- `init.lua` runtime guards: `local IS_SSH = (vim.env.SSH_CONNECTION or "") ~= ""` and `local HAS_DOTNET = vim.fn.executable("dotnet") == 1`. Use these to gate Mason / Rust-fuzzy / roslyn — don't introduce host-specific files.
- `.tmux.conf` portability: use `if-shell 'test "$(uname)" = Linux' '<linux-cmd>' '<mac-cmd>'`. Path-style differences via `$DOTFILES_DIR` exported from `.zshrc`.
- VS Code JSON files: LF line endings only.
- Symlinks: relative paths only — never hardcode `/Users/sfeng/`.

## Doc structure (keep aligned across all 3 repos)

Each repo has both `README.md` (human-facing) and `CLAUDE.md` (AI-operational). The split:

| `README.md` | `CLAUDE.md` |
|---|---|
| 1-2 sentence repo summary + sibling cross-refs | Source-of-truth identification (1 line) |
| Bootstrap commands (how to apply on a fresh machine) | **Behavior** — routing rules for edit requests by sync class. Required, near the top. This is what makes a fresh Claude session act correctly without an explicit `/init`. |
| Layout (full directory tree, path mappings) | Sync workflow + commands (what triggers when user says "sync dotfiles") |
| "Things you can ask Claude" — phrasings the user can use | Sync contract table (canonical only in dots-macos; siblings list partials + reference) |
| Concepts users should understand (vendoring, ASCII-only, symlink conventions) | Constraints (security, no-git-from-Mac, no-work-content, etc.) |
| Repo-specific extras (Mac setup checklist, gotchas, TODO) | Editing conventions (runtime guards, line endings, etc.) + this doc-structure section |

Rules:

- **Layout** lives in README only. CLAUDE.md may name specific files when they have operational rules attached, but doesn't repeat the tree.
- **Sync contract** lives in this CLAUDE.md only. Siblings reference it.
- **Sibling repo links** appear in both — README frames them as friendly cross-refs ("companion repo"), CLAUDE.md as source-of-truth relationship.
- **"Things you can ask Claude"** lives in README. Each phrasing maps to a concrete operation documented in CLAUDE.md (so the human prompt reliably triggers the AI behavior).

When you change something:

1. **Editing a byte-identical file** → run `sync-dotfiles.py --apply`. No doc changes.
2. **Adding a new shared dotfile** → add it to dots-macos, add a row to the sync contract above, add to `IDENTICAL` in `sync-dotfiles.py`, update layout in each affected README, and (if it changes user phrasings) update "Things you can ask Claude".
3. **Changing the sync workflow** (new script, new flag) → update this CLAUDE.md and the corresponding "Things you can ask Claude" entries in all 3 READMEs.
4. **Changing constraints or editing conventions** → update CLAUDE.md only (not README — operational).
5. **Always propagate cross-repo doc changes to all 3 repos** — both README and CLAUDE.md kept structurally aligned.
