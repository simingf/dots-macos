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
| neovim | `.config/nvim/lua/plugins/ui.lua` | rose-pine plugin (palette iris override) + highlight_groups + lualine + bufferline | `#ceacf6` |
| VS Code | `Library/Application Support/Code/User/settings.json` | `workbench.colorTheme = "Rosé Pine"` | canonical |
| zsh prompt | `.config/ohmyposh/zen.toml` | oh-my-posh palette; path + caret = iris | `#ceacf6` |
| zsh fzf | `.config/zsh/80-tools.zsh` | `FZF_DEFAULT_OPTS` (pointer/prompt/marker/border) | `#ceacf6` |
| zsh syntax | `.config/zsh/10-plugins.zsh` (linux: `80-tools.zsh`) | `ZSH_HIGHLIGHT_STYLES` + autosuggest | `#ceacf6` |
| zsh files | `.zprofile` | `LS_COLORS` (dirs = iris) → ls/eza/completion | `#ceacf6` |
| lazygit | `Library/Application Support/lazygit/config.yml` | hand-rolled rose-pine | `#ceacf6` |
| Claude Code | `.claude/settings.json` (`theme = dark-ansi`) + `.claude/statusline-command.sh` | ANSI-inherited UI + iris statusline | UI canonical / statusline `#ceacf6` |
| borders | `.config/borders/bordersrc` | JankyBorders `active_color` | `#ceacf6` |
| herdr | `.config/herdr/config.toml` | `accent` | `#ceacf6` |
| yazi | `.config/yazi/theme.toml` + `flavors/rose-pine.yazi/` | Rose Pine flavor; filetype rules + `[mgr].cwd` path hand-tuned iris-forward (folders + path = iris; images→rose, docs→foam, exec→pine for differentiation) | folders/path `#ceacf6`, rest canonical |
| spotify-player | `.config/spotify-player/{app,theme}.toml` | `theme = rose_pine` | canonical |
| btop | `.config/btop/themes/rose-pine.theme` + `btop.conf` | hand-rolled rose-pine flavor (`color_theme = "rose-pine"`) | `#ceacf6` |
| git | `.gitconfig` | hand-rolled `[color]` (diff/status/branch/decorate); mirrored to linux | `#ceacf6` |
| ripgrep | `.config/ripgrep/rg.conf` | `--colors` RGB triples (path/line/match) | `#ceacf6` |
| glow (yazi md preview) | `.config/yazi/plugins/glow.yazi/rose-pine.json` | hand-rolled glamour style; `glow --style <json>` from `main.lua`. Themes all prose chrome (headings/emph/links/inline-code/quotes/lists/hr). Fenced-code syntax tokens use glow 3.0.0's built-in 256-color chroma (style JSON's `chroma` block is inert in this binary; kept for newer glow on the linux box). | `#ceacf6` prose |

## Not yet themed / off-theme

- **man-pages / Alfred** — unthemed (`LESS_TERMCAP` unset; Alfred theme is a GUI export).
