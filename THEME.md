# THEME.md — rose-pine theming registry

One theme everywhere: **Rose Pine**, **iris-forward**, on a single custom-bright iris accent.
This registers every place theming lives so a new tool can be matched to the rest.

## Palette

Canonical Rose Pine (main), with **iris overridden to a brighter custom value**:

| token | hex | role |
|---|---|---|
| base | `#191724` | window background |
| surface | `#1f1d2e` | raised background |
| overlay | `#26233a` | selected-line / message bg |
| muted | `#6e6a86` | inactive borders, dim text |
| subtle | `#908caa` | secondary text |
| text | `#e0def4` | foreground |
| love | `#eb6f92` | error / danger / unstaged |
| gold | `#f6c177` | activity / search / time |
| rose | `#ebbcba` | media, options |
| pine | `#31748f` | executables |
| foam | `#9ccfd8` | secondary / info |
| **iris** | **`#ceacf6`** | **dominant accent** (canonical is `#c4a7e7`) |
| highlight-med | `#403d52` | cherry-pick / kitty selection |

## Accent convention

- **Dominant accent = iris `#ceacf6`** — anything active, selected, or primary (active borders, current tab, prompt caret, selection, pointer, path).
- Semantic colors are shared: **gold** = activity/search/time, **love** = error, **foam** = secondary/info, **muted** = inactive/dim, **subtle** = secondary text.
- Tools driven by upstream rose-pine themes (VS Code, kitty, spotify-player, and anything under Claude's `dark-ansi` / ghostty ANSI) render the **canonical** iris `#c4a7e7`; hand-rolled configs use the brighter `#ceacf6`. (yazi ships the upstream flavor but its filetype/path accents are hand-tuned to `#ceacf6` — see below.)

## Where theming lives

| Tool | File | Mechanism | Accent |
|---|---|---|---|
| ghostty | `.config/ghostty/config` | `theme = Rose Pine` + iris cursor/selection | `#ceacf6` |
| kitty | `.config/kitty/current-theme.conf` | rose-pine hexes (alt terminal) | canonical |
| tmux | `.tmux.conf` | hand-rolled; active border/status/window/copy-mode | `#ceacf6` |
| neovim | `.config/nvim/lua/plugins/ui.lua` | rose-pine plugin (palette iris override) + highlight_groups + lualine + bufferline + snacks explorer (dir/symlink/broken groups mirror `LS_COLORS`: dir = iris) | `#ceacf6` |
| VS Code | `Library/Application Support/Code/User/settings.json` | `workbench.colorTheme = "Rosé Pine"` | canonical |
| zsh prompt | `.config/ohmyposh/zen.toml` | oh-my-posh palette; path + caret = iris | `#ceacf6` |
| zsh fzf | `.config/zsh/80-tools.zsh` | `FZF_DEFAULT_OPTS` (pointer/prompt/marker/border) | `#ceacf6` |
| zsh syntax | `.config/zsh/10-plugins.zsh` (linux: `80-tools.zsh`) | `ZSH_HIGHLIGHT_STYLES` + autosuggest | `#ceacf6` |
| zsh files | `.zprofile` | `LS_COLORS` — **canonical filetype/dir palette, source of truth** (dirs=iris, symlink=foam, exec=pine, archives=gold, images+media=rose, lock/log/bak=muted, orphan=love) → ls/eza/completion; mirrored by yazi + nvim snacks explorer | `#ceacf6` |
| lazygit | `Library/Application Support/lazygit/config.yml` | hand-rolled rose-pine | `#ceacf6` |
| Claude Code | `.claude/settings.json` (`theme = dark-ansi`) + `.claude/statusline-command.sh` | ANSI-inherited UI + iris statusline | UI canonical / statusline `#ceacf6` |
| borders | `.config/borders/bordersrc` | JankyBorders `active_color` | `#ceacf6` |
| herdr | `.config/herdr/config.toml` | `accent` | `#ceacf6` |
| yazi | `.config/yazi/theme.toml` + `flavors/rose-pine.yazi/` | Rose Pine flavor; `[filetype]` rules mirror `LS_COLORS` (dir=iris, images+media=rose, archives=gold, exec=pine, orphan=love, lock/log/bak=muted) + `[mgr].cwd` path = iris | folders/path `#ceacf6`, rest canonical |
| spotify-player | `.config/spotify-player/{app,theme}.toml` | `theme = rose_pine` | canonical |
| btop | `.config/btop/themes/rose-pine.theme` + `btop.conf` | hand-rolled rose-pine flavor (`color_theme = "rose-pine"`) | `#ceacf6` |
| git | `.gitconfig` | hand-rolled `[color]` (diff/status/branch/decorate); mirrored to linux | `#ceacf6` |
| ripgrep | `.config/ripgrep/rg.conf` | `--colors` RGB triples (path/line/match) | `#ceacf6` |
| glow (yazi md preview) | `.config/yazi/plugins/glow.yazi/rose-pine.json` | hand-rolled glamour style; `glow --style <json>` from `main.lua`. Themes all prose chrome (headings/emph/links/inline-code/quotes/lists/hr). Fenced-code syntax tokens use glow 3.0.0's built-in 256-color chroma (style JSON's `chroma` block is inert in this binary; kept for newer glow on the linux box). | `#ceacf6` prose |

## Sync contract

Two things are **canonical sources** the others mirror. When you edit a source, propagate to its mirrors in the same change.

### 1. Filetype / directory colors → `LS_COLORS` (`.zprofile`)

`LS_COLORS` is the source of truth for how files and directories are colored. `ls` / `eza` / zsh completion read it directly; two tools hand-mirror it (they can't read it):

| `LS_COLORS` key | meaning | palette | yazi `[filetype]` rule | nvim snacks group |
|---|---|---|---|---|
| `di` | directory | iris `#ceacf6` | `{ url = "*/" }` | `SnacksPickerDirectory` |
| `ln` | symlink | foam `#9ccfd8` | target-typed (n/a) | `SnacksPickerLink` |
| `or` | broken symlink | love `#eb6f92` | `is = "orphan"` | `SnacksPickerLinkBroken` |
| `ex` | executable | pine `#31748f` | `is = "exec"` | devicon only |
| archives | tar/zip/gz/… | gold `#f6c177` | `mime = "application/{…}"` | devicon only |
| images+media | jpg/png/mp3/mp4/… | rose `#ebbcba` | `mime = "image/*"`, `"{audio,video}/*"` | devicon only |
| lock/log/bak | transient | muted `#6e6a86` | `url = "*.lock"` … | devicon only |
| (regular file) | — | text `#e0def4` | `{ url = "*" }` | `SnacksPickerFile` (default) |

- **yazi** (`flavors/rose-pine.yazi/flavor.toml` → `[filetype].rules`) colors the **name** by mime/glob, so it mirrors `LS_COLORS` 1:1. Symlinks are the one gap: yazi types a valid symlink by its target (only broken links get `is = "orphan"`), so `ln` has no direct rule.
- **nvim snacks explorer** (`lua/plugins/ui.lua` → `style_picker()`) colors names only by **category** (dir / file / symlink / broken / hidden). Per-extension type color rides on the **devicon**, never the name — so only `di` / `ln` / `or` map to name highlight groups; archive/image/etc. colors can't be mirrored onto names here.

### 2. Accent (iris) → Palette table (top of this doc)

Bright `#ceacf6` in hand-rolled configs, canonical `#c4a7e7` in upstream-flavor-driven tools (see **Accent convention**). Changing the accent means updating every hand-rolled row in **Where theming lives**.

### Adding a new themed tool

Pick its accent per the convention, add a row to **Where theming lives**, and — if it colors files/dirs — mirror `LS_COLORS` per the table above.

> THEME.md is a mac-only doc, but the configs it governs (yazi flavor, nvim lua) sync to the linux/windows repos per the repo `CLAUDE.md` sync contract. A palette edit here still has to be applied + synced there.

## Not yet themed / off-theme

- **man-pages / Alfred** — unthemed (`LESS_TERMCAP` unset; Alfred theme is a GUI export).
