# dots-macos — Claude Instructions

`~/dots-macos` is the **source of truth** for all three dotfile repos:

- `~/dots-linux` — public on github.rbx.com; Coder applies on Linux dev boxes (`*.coder`). No internet on the box, so plugins/terminfo are vendored.
- `~/dots-windows` — personal Windows. **Must contain no work content.**

`~/dots-macos` is also cloned on the Linux dev box (next to `~/dots-linux`; no `~/dots-windows` there). The same edit-here-then-`sync-dotfiles.py --apply` workflow runs from that clone (the windows target is skipped). The box's live config is still `~/dots-linux` — a dots-macos edit only takes effect there after the sync. `refresh-linux*.sh` refuse to run off the Mac (they vendor the Mac's plugin trees and need internet).

For repo layout and bootstrap, see [`README.md`](./README.md).

## Behavior

When the user asks you to edit a file, route by sync class (see contract below):

- **Byte-identical** with a sibling: edit here (Mac is source), then run `scripts/sync-dotfiles.py --apply` in the same task. Idempotent.
- **Partial** (e.g., `.config/zsh/70-platform.zsh`, `.gitconfig`, Windows `Profile.ps1`): edit here, then judge whether to hand-mirror. Generic changes (new alias/function) propagate to siblings, **translating Mac-only tools out** (`trash`, `pbcopy`, oh-my-posh, homebrew, `/Applications/`). Platform-specific changes don't. Ask if unsure.
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
   - byte-identical → add to `IDENTICAL["linux"]` / `IDENTICAL["windows"]` (or a whole tree to `IDENTICAL_DIRS`) in `scripts/sync-dotfiles.py`, then `--apply` to seed.
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

When the user says **"refresh Linux vendored plugins"**, run the one-shot orchestrator:

```bash
~/dots-macos/scripts/refresh-linux.sh
```

Hands-off: (1) `nvim Lazy! sync` + `zinit update` on the Mac, plus `tmux-agent-state.py update-rules` (stops unless `test-agent-state.py` passes), (2) `refresh-linux-vendored.sh` re-vendors plugins + binaries + nvim LSP servers (at the Mac's mason versions; the box has no mason) into dots-linux, (3) `sync-dotfiles.py --apply linux`, (4) commit + push both repos. Any failing step stops with `FAILED (line N): <command>` — including a Lazy plugin that failed to sync (nvim itself exits 0).

Commits: `vendor/` is committed with `SKIP=gitleaks` (third-party bytes trip Roblox's gitleaks hook with false positives). Config commits (lazy-lock.json, …) are scanned normally, so a real secret still blocks. `git push` is never scanned (the infosec `git` wrapper only gates `commit`). Commits are pathspec-scoped to the refresh footprint (nvim lazy-lock, `scripts/agent-detection/`), so unrelated pending work isn't swept in. Details: header of `scripts/refresh-linux.sh`.

## Sync contract

Byte-identical = listed in `IDENTICAL` / `IDENTICAL_DIRS` of `scripts/sync-dotfiles.py` (the authority — keep this table in step with it).

| File / dir | linux | windows | Rule |
|---|---|---|---|
| `.tmux.conf` | byte-identical | — | Needs tmux ≥3.5 (`pane-title-changed` / `window-layout-changed` hooks drive the agent dots + lazygit sidebar; older tmux silently ignores them). Linux gets a vendored static tmux (`dots-linux/vendor/bin/tmux`, shadows `/usr/bin` via `~/.local/bin`; one `tmux kill-server` after first `setup.sh`). Same `C-Space` prefix on both. `$DOTFILES_DIR` is set into tmux's global env by a `run-shell` at the top, so it works on a server started without the shell export. Only platform branch: `if-shell '[ -x /usr/bin/zsh ]'` for default-shell. |
| `.config/nvim/init.lua` | byte-identical | byte-identical | Thin loader: `config.{options,keymaps,autocmds}` → `config.lazy` → `config.tmux_lazygit` + `config.healthcheck`. |
| `.config/nvim/lua/**` | byte-identical | byte-identical | **Dir-mirrored** (`IDENTICAL_DIRS`): new/removed files propagate automatically. `lua/config/*` (options, keymaps, autocmds, env, lazy, nav, tabs, preview, healthcheck, tmux_lazygit) + `lua/plugins/*` (auto-imported). Host differences only via guards in `lua/config/env.lua`. |
| `.config/nvim/lazy-lock.json` | byte-identical | byte-identical | |
| `.config/nvim/FRAGILE.md` | — | — | Mac-only brittle-spots audit (not synced, like `THEME.md`). The `healthcheck.lua` it references does sync; `:ConfigHealth` for the full report. |
| `scripts/tmux-*.sh`, `scripts/tmux-agent-state.py`, `scripts/agent-detection/{claude.toml,claude.json,LICENSE}`, `scripts/lazygit-tmux-edit.yml` | byte-identical | — | Called from `.tmux.conf` / hooks via `$DOTFILES_DIR`. Each script's header documents its behavior; operational notes below the table. |
| `.config/yazi/` (toml configs, `flavors/rose-pine.yazi/`, `plugins/glow.yazi/{main.lua,rose-pine.json}`, `package.toml`) | byte-identical | byte-identical | Listed file by file — a new yazi file must be added to **both** `IDENTICAL["linux"]` and `IDENTICAL["windows"]`. Linux `yazi`+`ya` vendored in `dots-linux/vendor/bin/`. Windows: `apply.ps1` links the dir and sets `YAZI_CONFIG_HOME` + `YAZI_FILE_ONE`. |
| `Library/Application Support/lazygit/config.yml` | byte-identical | byte-identical | `keybinding:` is a pure m↔h n↔j e↔k i↔l swap of the defaults (KEYBINDS.md) — keep it a permutation when lazygit adds defaults on those letters. Paths: linux `.config/lazygit/config.yml` (**file-level** link; lazygit writes `state.yml` there), windows `AppData/Roaming/lazygit/`. |
| `Library/Application Support/Code/User/{settings,keybindings}.json` | — | byte-identical | LF line endings. |
| `.config/{ripgrep/rg.conf, gh/config.yml}` | — | byte-identical | Windows: `rg.conf` read via `RIPGREP_CONFIG_PATH`; gh at `AppData/Roaming/GitHub CLI/`. Not on linux (gh rewrites `config.yml`, which would replace a symlink). |
| `.config/ohmyposh/zen.toml` | byte-identical | byte-identical | Linux runs the vendored `oh-my-posh`; `20-prompt.zsh` falls back to an iris `vcs_info` prompt if it's missing (or under Apple Terminal). Windows reads it from the repo via `Profile.ps1`. |
| `.zprofile` | — | — | **Mac-only** login env (homebrew, PATH additions, `RIPGREP_CONFIG_PATH`, `ANI_CLI_PLAYER`, `unset GH_TOKEN`). Linux shells/tmux panes are non-login, so anything an interactive feature needs goes in `00-env.zsh`, never here. |
| `.zshrc` | byte-identical | — | Loader only: sources `~/.config/zsh/[0-9]*.zsh`. If declawd's installer re-appends a `~/.local/bin` PATH line, delete it (`00-env.zsh` already has it). |
| `.config/zsh/{00-env,00-history,20-prompt,30-interactive,50-aliases,60-functions,80-tools,90-agent,95-session}.zsh` | byte-identical | — | Shared modules. `00-env` (env, `DOTFILES_DIR` from its own real path), `20-prompt`, `30-interactive` (keybindings + the GUI-style line-editing widgets for the ⌘ keys), `50-aliases`, `60-functions`, `80-tools` (fzf/zoxide/direnv/nvm, highlight colors), `90-agent` (drops coreutils-shadowing aliases under `$AI_AGENT`), `95-session` (sources `mux-tmux.zsh`). Guard optional tools with `command -v`, never OS checks. Windows' counterpart is the hand-translated `Profile.ps1`. |
| `.config/zsh/{10-plugins,70-platform}.zsh` | partial | — | The only per-platform modules. `10-plugins`: zinit turbo (mac) vs vendored plugins (linux; zsh-syntax-highlighting deferred to the first prompt). `70-platform`: platform-only aliases/functions — mac: Finder/brew/app aliases, `dotsl`/`dotsw`, `claude` → declawd sandbox, `k`, `s`, conda lazy-load, `c`; linux: `GCC_COLORS`, `BROWSER` → `scripts/open-url.sh`, `c`, `vim=nvim`, `claude` → raw `--dangerously-skip-permissions`. New aliases/functions go in the shared modules unless they need a platform-only tool or path. |
| `.config/zsh/mux-tmux.zsh` | byte-identical | — | tmux session helpers (`kk` = nvim \| claude split, `tn`/`ta`/`tk`/`runall`/`rsa`). No host paths. Relies on `claude` (`70-platform`) and `_REAL_TMUX` (`30-interactive`). |
| `.gitconfig` (+ `.config/git/github-roblox.inc`, Mac-only) | partial | — | Order: `[user]` + functional config + `[include] path = ~/.config/git/common.inc` first, **credentials last**. Mac: generic `[credential] helper = …gcm` block **before** the per-host `osxkeychain` blocks for `github.com` / `github.rbx.com` (else its empty-reset wipes them; verify with `printf 'protocol=https\nhost=github.rbx.com\n\n' \| GIT_TRACE=1 git credential fill`). Two `github.com` accounts: `simingf` default, `sfeng-roblox` for `github.com/Roblox/*` via `[includeIf "hasconfig:remote.*.url:…"]` → `github-roblox.inc`, which must come after the credential blocks. `setup.sh` seeds the three PATs into the keychain. Linux: `[user]` + include by repo path + a `github.rbx.com` `store` helper (for Coder's rbx-skills startup check); the real PAT helper lives in `.config/git/config` (XDG, so Coder's per-boot `~/.gitconfig` clobber can't win). Credentials never live in the repo. |
| `.config/git/{common.inc,ignore}` | byte-identical | byte-identical | `common.inc` (pull/push defaults + rose-pine colors) via `[include]`: mac stowed path, linux repo path, windows `include.path` from `apply.ps1`. `ignore` sits at git's default excludesfile path (no `core.excludesfile`): stowed on mac, file-level link on linux/windows. |
| `.claude/CLAUDE.md` | byte-identical | byte-identical | Global Claude Code instructions. |
| `.claude/settings.json` | byte-identical | — | Has the work MCP allowlist — never sync to windows (it has its own minimal one). |
| `.claude/statusline-command.sh` | byte-identical | byte-identical | Needs `jq`. Windows wires it via its own `settings.json`; `.gitattributes` keeps it LF. |
| `.claude/themes/rose-pine.json` | byte-identical | byte-identical | `"theme": "custom:rose-pine"`. |
| `.claude/hooks/agent-notify.sh` | byte-identical | — | Stop/Notification → `tmux-notify.sh` status-bar notice; silent no-op outside tmux / with no attached client. |
| `.claude/hooks/agent-status.sh` | byte-identical | — | Lifecycle hooks → flags in `/tmp/agent-status-<uid>-<pane>` the screen can't show (`errored`, `compacting`), then nudges `tmux-agents.sh refresh`. Working/waiting/idle are screen-detected by `tmux-agent-state.py`. |
| `.claude/hooks/agent-clip.py` | byte-identical | — | Stop → copies each user-facing block of the reply (fenced blocks, `>` quotes, `! cmd`; skips commands the agent ran) to the clipboard, one `pbcopy` per block 1s apart (Alfred history). Linux `pbcopy` = `dots-linux/bin/pbcopy` (OSC 52). Pairs with the global CLAUDE.md formatting rule; agents never pbcopy themselves. See its header. |
| `Documents/PowerShell/Profile.ps1` (in dots-windows) | — | partial | Hand-translated subset of the shared zsh modules (no work helpers). Rose-pine `LS_COLORS` / `FZF_DEFAULT_OPTS` / PSReadLine colors are hand copies of `00-env` / `80-tools` — update on palette changes. |
| `.bashrc`, `vendor/`, `bin/`, `setup.sh`, `install.sh`, `.config/git/config`, `roblox/`, `scripts/{setup-roblox,open-url}.sh` (in dots-linux) | Linux-only | — | |
| `AppData/Local/Packages/Microsoft.WindowsTerminal_…/`, `scripts/apply.ps1`, `.claude/settings.json`, `.gitattributes` (in dots-windows) | — | Windows-only | `.gitattributes` pins `*.sh` to LF for Git Bash. |
| `.config/finicky/finicky.ts` | — | — | Mac-only. Routes every external link to the `Default` Chrome profile (work). |
| `scripts/test-agent-state.py` | — | — | Mac-only offline test of `tmux-agent-state.py`. Run after `update-rules` or an engine change. |
| `scripts/karabiner-hold-leaders.py` | — | — | Mac-only generator for the first rule of `.config/karabiner/karabiner.json` (found by its `Generated by …` suffix — never hand-edit that rule). Ghostty-only: hold right ⌘ / right ⌥ → `C-Space` / `Space` before each key. Covers every key, so bind changes need no re-run. This is why `.tmux.conf` has no `-r` binds (`repeat-time 0`) and nvim has no repeatable leader maps — chaining = keep holding. |
| `scripts/test-keybinds.py` | — | — | Mac-only end-to-end test of the ⌘-key / selection keybinds on private tmux sockets (never touches the live server). |
| `Library/` (rest), `Brewfile`, `manual/`, `learnings/`, `archive/`, `.ssh/`, `.vimrc`, `alfred/`, `ghostty/`, `kitty/`, `aerospace/`, `karabiner/`, `borders/`, `btop/`, `istherenet/`, `linearmouse/`, `spotify-player/`, `.config/topgrade.toml` | Mac-only | Mac-only | Do NOT mirror. `learnings/`: debugging write-ups. `archive/`: retired features parked for restore (e.g. `archive/agent-sidebar/`). |

`.claude/` is whitelisted in the Mac `.gitignore` (`.claude/*` + `!` negations): a new tracked `.claude/` file needs its own negation. dots-linux doesn't ignore `.claude/`.

### tmux scripts — operational notes

Behavior lives in each script's header; these are the rules an editor needs.

- **`tmux-agent-state.py` + `agent-detection/`** — port of [herdr](https://github.com/herdrdev/herdr)'s rule engine over each pane's title + screen. `claude.toml` is herdr's manifest **vendored verbatim** (Apache-2.0 `LICENSE` beside it); `claude.json` is generated from it by `update-rules` (`tomllib` is 3.11+). **Never edit either by hand** — refresh via `refresh-linux.sh` or `tmux-agent-state.py update-rules` then `scripts/test-agent-state.py`. Must stay stdlib-only Python ≥3.8 (runs on the box). Debug a wrong dot with `tmux-agent-state.py explain <pane>`.
- **`tmux-agents.sh`** — agent glue: `prefix a` picker, status-bar count, tab dots. `count` (status-right, `status-interval` 2s) doubles as the dot poll. `mark-read` runs on every focus-change hook.
- **`tmux-lazygit.sh` + `lazygit-tmux-edit.yml`** — `prefix g` lazygit sidebar (tagged `@sidebar=1`, which `tmux-even-columns.sh` and pane counts respect). Closing parks lazygit in the hidden `_lazygit` session; **sessions named `_*` are hidden** from the session pickers, `tl`/`ta`/`tk` and pane search. Repo choice + nvim follow uses `@nvim_repo` / `@nvim_server` published by `lua/config/tmux_lazygit.lua`. The edit overlay is a separate yml layered on by `lg` inside tmux — keep it out of the shared `config.yml` (windows reads that).
- **`tmux-nav.sh`** — `prefix m/n/e/i` and nvim `<leader>m/n/e/i`: asks nvim over RPC (`v:lua.TmuxNav` / `TmuxNavEnter` in `lua/config/nav.lua`) before crossing to the next tmux pane.
- **`tmux-even-columns.sh`** — `prefix 0` equal columns (sidebar keeps its width, stacks stay stacked); keep mode after `prefix M`/`I` and border drags. Unsupported shapes are left as-is.
- **`tmux-layout-classic.sh`** — tmux ≥3.8 reports `#{window_layout}` as JSON but `select-layout` still takes the classic string; the layout rewriters convert on read through this.
- **`tmux-cmdkey.sh`** — ⌘-key dispatcher behind root `User0`–`User16` (see Editing conventions, ⌘ shortcuts). Routing order matters: zsh-at-prompt is tested **before** the Claude test (a stale `✳` title can outlive Claude). `.tmux.conf` sets `status-keys emacs` so Esc cancels the ⌘F prompt.
- **`tmux-notify.sh`** — transient notice in a `status-right` segment (`@notify`). Deliberately not a popup: tmux popups are always modal. Native tmux messages can't be rerouted, so only commands from our own binds are wrapped (hence the guarded `prefix 1`–`9`). With `NOTIFY_TARGET=$TMUX_PANE` it only fires if a client is attached to that session.
- **`tmux-copy-dragend.sh`** — copies + clears a mouse selection released outside its pane (other pane, status bar, border).
- **`tmux-fzf-*.sh`, `tmux-rename.sh`** — `prefix s`/`w`/`f`/`@` pickers and `prefix r`/`R`/`C` name prompts, all in centered `display-popup`s (chrome set globally in `.tmux.conf`). A window rename also sends `/rename <name>` to that window's Claude pane(s).

## Scripts policy

- **Bootstrap** lives in its own repo (`dots-macos/scripts/setup.sh`, `dots-linux/setup.sh`, `dots-windows/scripts/apply.ps1`) — each runs on the platform it applies.
- **Cross-repo orchestration** lives in `dots-macos/scripts/` (`sync-dotfiles.py`, `refresh-linux-vendored.sh`, `refresh-linux.sh`) since Mac is the control plane.
- **Config helpers** (`scripts/tmux-*.sh`) live in every repo where the calling config runs, synced byte-identical.

## Editing conventions

- nvim runtime guards live in `.config/nvim/lua/config/env.lua` (`IS_SSH`, `HAS_DOTNET`). Plugin files do `local env = require("config.env")` and gate on `env.IS_SSH` / `env.HAS_DOTNET` (Mason / Rust-fuzzy / roslyn). Don't introduce host-specific files — keep the byte-identical tree + guards.
- `.tmux.conf` portability: platform branches use `if-shell '<test>' '<a>' '<b>'`. Reference scripts as `$DOTFILES_DIR/scripts/…` (tmux doesn't expand `~`/`$HOME`; the top-of-file `run-shell` resolves it).
- zsh portability: shared modules stay byte-identical — guard optional tools with `command -v <tool>` (or `[[ -f … ]]` for plugin files), reference repo paths via `$DOTFILES_DIR`, never `~/dots-macos`. Platform-only tools/paths go in that platform's `70-platform.zsh` (or `10-plugins.zsh`) — no `$OSTYPE` branches in shared modules.
- **⌘ shortcuts** (one path for zsh / nvim / Claude Code, Mac and Linux): ghostty `keybind = cmd+<key>=text:\x1b[90NN~` (Mac-only config) → `.tmux.conf` `user-keys[N]` + `bind -n UserN run-shell …tmux-cmdkey.sh …` → a `case` arm per app in `scripts/tmux-cmdkey.sh` (zsh: forward the bytes, `bindkey` a widget in `30-interactive.zsh`; nvim: kitty-style super CSI-u, mapped as `<D-…>` in `lua/config/keymaps.lua`; Claude: a Ctrl key it understands). A new ⌘ key touches all four, plus `KEYBINDS.md` and a case in `scripts/test-keybinds.py` — run it (`-k <text>` for a subset) after any change to these keys. Never rely on ghostty-only behavior (native selection, `cursor-click-to-move`) — it can't reach the remote tmux.
- nvim keymap hygiene: no x/o-mode map may start with `i` (the `i`↔`l` swap makes `i` a motion there; a longer `i…` map would make every `i` wait out `timeoutlen`) — rehome inner objects to `l…`. Register new keybinds (and deliberately disabled keys) in `KEYBINDS.md`.
- VS Code JSON files: LF only.
- Symlinks: relative paths only — never hardcode `/Users/sfeng/`.
- **Plists: never symlink.** macOS `cfprefsd` atomically replaces plist files, breaking symlinks. Store app plists in `manual/preferences/` and restore via `cp` in `scripts/setup.sh`. To snapshot: `cp ~/Library/Preferences/<domain>.plist manual/preferences/`.
- **macOS GUI apps launched from tmux** inherit a non-GUI audit session: direct-exec'd `.app` binaries (or CLIs that exec them, e.g. `iina-cli`) draw windows but get no menu bar / cmd-tab / activation. Wrap in `/usr/bin/open -na <App> --args …` — pattern: `scripts/iina-cli-activate.sh` (`ANI_CLI_PLAYER` in `.zprofile`). `reattach-to-user-namespace` does **not** fix this.

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
