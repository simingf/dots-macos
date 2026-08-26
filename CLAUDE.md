# dots-macos — Claude Instructions

`~/dots-macos` is the **source of truth** for all three dotfile repos:

- `~/dots-linux` — public on github.rbx.com; Coder applies on Linux dev boxes (`*.coder`). No internet on the box, so plugins/terminfo are vendored.
- `~/dots-windows` — personal Windows. **Must contain no work content.**

For repo layout and bootstrap, see [`README.md`](./README.md).

## Behavior

When the user asks you to edit a file, route by sync class (see contract below):

- **Byte-identical** with a sibling: edit here (Mac is source), then run `scripts/sync-dotfiles.py --apply` in the same task. Idempotent.
- **Partial** (e.g., `.zshrc`, `.gitconfig`): edit here, then judge whether to hand-mirror. Generic changes (new alias/function) propagate to siblings, **translating Mac-only tools out** (`trash`, `pbcopy`, oh-my-posh, homebrew, `/Applications/`). Platform-specific changes don't. Ask if unsure.
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
| `.tmux.conf` | byte-identical | — | Unified `C-Space` prefix on both (no uname split). `$DOTFILES_DIR` (used by the `scripts/*.sh` binds/hooks) is resolved into tmux's own global env at load — `run-shell 'tmux set-environment -g DOTFILES_DIR "$HOME/dots-$([ "$(uname)" = Linux ] && echo linux || echo macos)"'` — so it works even on a persistent server started without the shell export. Remaining platform branch: `if-shell '[ -x /usr/bin/zsh ]'` for default-shell. |
| `.config/nvim/init.lua` | byte-identical | byte-identical | Thin loader: requires `config.{options,keymaps,autocmds}` then `config.lazy`. |
| `.config/nvim/lua/**` | byte-identical | byte-identical | Config split, lazy.nvim standard layout: `lua/config/*.lua` (options, keymaps, autocmds, `env`, lazy bootstrap) + `lua/plugins/*.lua` (topical: deps/ui/editor/navigation/treesitter/lsp/coding/git/ai) auto-imported via `import = "plugins"`. Whole tree **dir-mirrored** by `sync-dotfiles.py` (`IDENTICAL_DIRS`) — add a plugin file, it auto-syncs. Host guards live in `lua/config/env.lua`. |
| `.config/nvim/lazy-lock.json` | byte-identical | byte-identical | |
| `scripts/tmux-fzf-*.sh`, `scripts/tmux-agents.sh` | byte-identical | — | Called from `.tmux.conf` via `$DOTFILES_DIR`. `tmux-agents.sh` detects agent panes by the OSC title captured in `#{pane_title}` (braille spinner = working, idle marker = idle) — powers `prefix a` picker, the `prefix A` / `prefix c`-seeded left sidebar (a clickable fzf panel), and the status-bar count. |
| `.config/yazi/{yazi,keymap,theme}.toml` + `flavors/rose-pine.yazi/{flavor.toml,tmtheme.xml}` | byte-identical | — | Linux `yazi`+`ya` binaries vendored under `dots-linux/vendor/bin/`. New yazi files must be added to `IDENTICAL["linux"]` in `sync-dotfiles.py`. |
| `Library/Application Support/lazygit/config.yml` | — | byte-identical | |
| `Library/Application Support/Code/User/{settings,keybindings}.json` | — | byte-identical | LF line endings (Mac normalized). |
| `.config/{ohmyposh/zen.toml, ripgrep/rg.conf, gh/config.yml}` | — | byte-identical | |
| `.zprofile` | partial | — | Mac has homebrew shellenv, conda/TeX/rustup/iina PATH entries. Linux has `GCC_COLORS`, devspace env vars, no homebrew. Both share `EDITOR`, `LS_COLORS`, `GH_HOST`, `NVM_DIR`, `~/.local/bin` + `skills-cli` PATH. |
| `.zshrc` | partial | — | Thin loader only: `for _f in ~/.config/zsh/[0-9]*.zsh(N); do source $_f; done` (mac then appends declawd's PATH line). Identical loader line on both. |
| `.config/zsh/NN-*.zsh` | partial | — | Ordered config modules, sourced in numeric order by the loader: `00-history`, `10-plugins` (zinit vs vendored), `20-prompt` (oh-my-posh vs `vcs_info`), `30-interactive` (keybindings/hooks/completion/clear-ls/`_REAL_TMUX`), `50-aliases`, `60-functions` (incl `sup`, `claude`, `kk` fallback), `80-tools`, `90-agent`, `95-session`. Linux adds `00-env` (the `~/.local/bin` PATH guard). **Partial per-platform** — hand-mirror generic changes, translating Mac-only tools out. |
| `.config/zsh/mux-tmux.zsh` | byte-identical | — | tmux session module: tmux `kk` split (mirrors the herdr layout) + `tn`/`ta`/`tk`/`runall`/`rsa` + tmux aliases. Sourced by `95-session.zsh` inside a real tmux. Byte-identical — no host paths (`claude`/`nvim`/`lazygit` resolve per-platform). `mux-herdr.zsh` is **Mac-only** (herdr `kk` + `_kk_split`), not mirrored. Both rely on `_kk_recent_nested_repo`/`claude`/`_REAL_TMUX` from `30-interactive`/`60-functions`. |
| `.gitconfig` | partial | — | Linux is minimal: `user.name` + `github.rbx.com` credential helper. Mac has personal+work GH accounts, LFS, GCM, maintenance. |
| `.claude/CLAUDE.md` | byte-identical | byte-identical | Global Claude Code instructions. Platform-agnostic. |
| `.claude/settings.json` | byte-identical | — | Claude Code settings (contains work MCP allowlist). File-level symlink. |
| `.claude/statusline-command.sh` | byte-identical | byte-identical | Status-line renderer. File-level symlink. |
| `.claude/hooks/agent-notify.sh` | byte-identical | — | Stop/Notification → desktop toast (`terminal-notifier`/`osascript` Mac, `notify-send` Linux); no-ops under herdr (`HERDR_ENV=1`) and where no notifier exists. Wired in `.claude/settings.json`. Un-ignored via a `!.claude/hooks/agent-notify.sh` negation in `.gitignore` — **sibling `.gitignore`s need the same negation** to track the synced copy (herdr's own `herdr-agent-state.sh` stays ignored). |
| `Documents/PowerShell/Profile.ps1` (in dots-windows) | — | partial | Hand-translated subset of `.zshrc`. |
| `.bashrc`, `vendor/`, `setup.sh` | Linux-only | — | |
| `AppData/Local/Packages/Microsoft.WindowsTerminal_…/`, `scripts/apply.ps1` | — | Windows-only | |
| `.config/finicky/finicky.ts` | — | — | Mac-only. Routes every external link to the `Default` Chrome profile (work). |
| `Library/` (rest), `Brewfile`, `manual/`, `learnings/`, `alfred/`, `ghostty/`, `herdr/`, `kitty/`, `aerospace/`, `karabiner/`, `borders/`, `btop/`, `istherenet/`, `linearmouse/`, `spotify-player/`, `.config/topgrade.toml` | Mac-only | Mac-only | Do NOT mirror. `herdr/`: only `config.toml` tracked (file-level symlink; dir holds sockets/logs/`session.json`). `learnings/`: debugging write-ups, not config. |

## Scripts policy

- **Bootstrap** lives in its own repo (`dots-macos/scripts/setup.sh`, `dots-linux/setup.sh`, `dots-windows/scripts/apply.ps1`) — each runs on the platform it applies.
- **Cross-repo orchestration** lives in `dots-macos/scripts/` (`sync-dotfiles.py`, `refresh-linux-vendored.sh`) since Mac is the control plane.
- **Config helpers** (`scripts/tmux-fzf-*.sh`) live in every repo where the calling config runs, synced byte-identical.

## Editing conventions

- nvim runtime guards live in `.config/nvim/lua/config/env.lua` (`return { IS_SSH = (vim.env.SSH_CONNECTION or "") ~= "", HAS_DOTNET = vim.fn.executable("dotnet") == 1 }`). Plugin files that gate on them do `local env = require("config.env")` and read `env.IS_SSH` / `env.HAS_DOTNET` (Mason / Rust-fuzzy / roslyn). Don't introduce host-specific files — keep the byte-identical tree + guards.
- `.tmux.conf` portability: platform branches use `if-shell '<test>' '<a>' '<b>'` (e.g. `[ -x /usr/bin/zsh ]` for default-shell). `$DOTFILES_DIR` (for `scripts/*.sh` binds/hooks) is resolved into tmux's global env at the top of `.tmux.conf` via `run-shell 'tmux set-environment -g DOTFILES_DIR ...'` — tmux doesn't expand `~`/`$HOME`, so sh resolves it; this survives a server started without the shell export.
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
