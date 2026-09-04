# KEYBINDS.md — keybind registry

One directional schema everywhere: **Colemak-DH `mnei`** in place of `hjkl`. This registers
every keybind across the systems that share that schema (nvim, tmux, AeroSpace) so a new
binding can be matched to the rest. Theming has a sibling registry in [`THEME.md`](./THEME.md).

## The schema

`hjkl` is replaced by **`mnei`** for every directional action, in every system:

| Key | Direction | Why not `hjkl` |
|---|---|---|
| `m` | ← left | `h`/`H` are claimed by arrow.nvim (nvim); `m` is the reachable stand-in |
| `n` | ↓ down | `n`/`e`/`i` sit on the Colemak-DH home row (QWERTY `j`/`k`/`l` positions) |
| `e` | ↑ up | |
| `i` | → right | |

Two motions displaced by the swap are rehomed consistently in **both nvim and tmux copy-mode**:

- **`j` / `J`** → repeat search forward / backward (took over from `n`/`N`).
- **`k`** → word-end motion (took over from `e`).

Modifier prefix per system: **nvim** `<leader>` = Space · **tmux** prefix = `C-Space` (emitted by
a right-cmd tap via Karabiner) · **AeroSpace** = `alt`.

### Directional matrix (the same four keys, per context)

| Context | left | down | up | right | File |
|---|---|---|---|---|---|
| nvim cursor (n/x/o) | `m` | `n` | `e` | `i`¹ | `…/lua/config/keymaps.lua` |
| nvim windows | `<leader>m` | `<leader>n` | `<leader>e` | `<leader>i` | `…/lua/config/keymaps.lua` |
| tmux pane select | `‹pfx›m` | `‹pfx›n` | `‹pfx›e` | `‹pfx›i` | `.tmux.conf` |
| tmux pane resize | `‹pfx›M` | `‹pfx›N` | `‹pfx›E` | `‹pfx›I` | `.tmux.conf` |
| tmux copy-mode | `m` | `n` | `e` | `i` | `.tmux.conf` |
| AeroSpace focus | `alt-m` | `alt-n` | `alt-e` | `alt-i` | `.config/aerospace/aerospace.toml` |
| AeroSpace join-with | `alt-shift-m` | `alt-shift-n` | `alt-shift-e` | `alt-shift-i` | `.config/aerospace/aerospace.toml` |

¹ `i`→right and `l`→insert are swapped **only in normal mode**, so visual/operator-pending keep `i`
as the text-object prefix (`vi(`, `ci{`, treesitter `if`/`ic`). AeroSpace **move-window** stays on
`alt-arrows` (layout-neutral, so no letter to remap).

---

## nvim — core

`.config/nvim/lua/config/keymaps.lua`. Leader = `Space`.

| Key | Action | Mode |
|---|---|---|
| `m` `n` `e` | left / down / up (→ `h` `j` `k`) | n, x, o |
| `i` | right (→ `l`) | n |
| `l` | insert (→ `i`) | n |
| `j` / `J` | search repeat forward / backward (→ `n` / `N`) | n, x |
| `k` | word-end (→ `e`) | n, x, o |
| `<leader>m` `<leader>n` `<leader>e` `<leader>i` | focus window left / down / up / right | n |
| `<leader>\` | vertical split | n |
| `<leader>-` | horizontal split | n |
| `<leader>j` | join lines (rehomed from `J`; `gJ` still joins w/o space) | n, x |
| `0` / `L` | line start (`^`) / line end (`$`) | n, x, o |
| `x` / `X` | delete char / line to black-hole register | n, x |
| `gy` / `gp` | yank to / paste from system clipboard | n,x / n |
| `<leader>f` | format buffer (conform → LSP fallback) | n, x |

Also `:FormatDisable[!]` / `:FormatEnable` toggle format-on-save (buffer / global).

## nvim — plugins

All under `.config/nvim/lua/plugins/`.

| Key | Action | Plugin | File |
|---|---|---|---|
| `<leader><leader>` | buffer-local keymap hints | which-key | `ui.lua` |
| `<leader>w` · `<leader>x` · `<leader>t` · `<leader>b` | groups: windows · trouble · pickers · buffer | which-key | `ui.lua` |
| `<leader>bi` / `<leader>bm` | next / prev buffer | bufferline | `ui.lua` |
| `<leader>bp` | pick buffer (jump by letter) | bufferline | `ui.lua` |
| `<leader>bc` | close buffer | snacks.bufdelete | `ui.lua` |
| `<leader>br` | re-render inline image | snacks.image | `ui.lua` |
| `<leader>tt` | fuzzy find in buffer | snacks.picker | `ui.lua` |
| `<leader>tg` | live grep | snacks.picker | `ui.lua` |
| `<leader>tb` | buffers | snacks.picker | `ui.lua` |
| `<leader>tf` | find files | snacks.picker | `ui.lua` |
| `<leader>tr` | recent files | snacks.picker | `ui.lua` |
| `<leader>td` | diagnostics | snacks.picker | `ui.lua` |
| `<leader>tn` | notifications | snacks.picker | `ui.lua` |
| `<leader>ty` | yank-ring history | yanky | `editor.lua` |
| `s` / `S` | flash jump / treesitter jump | flash | `editor.lua` |
| `r` (o) / `R` (o,x) | remote flash / treesitter search | flash | `editor.lua` |
| `H` / `h` | bookmark: global / buffer leader | arrow.nvim | `editor.lua` |
| `q` `Q` `<C-q>` `cq` `dq` `yq` | macro: rec · play · slot · edit · delete-all · yank | recorder | `editor.lua` |
| `<leader>\`` | reveal / leave file tree | snacks.explorer | `navigation.lua` |
| `<leader>y` / `<leader>Y` | yazi @ current file / cwd | yazi.nvim | `navigation.lua` |
| `<leader>p` | markdown preview toggle | markdown-preview | `treesitter.lua` |
| `af`/`if` · `ac`/`ic` · `as` | text-objects: function · class · scope | ts-textobjects | `treesitter.lua` (x, o) |
| `<leader>xx` / `<leader>xX` | diagnostics / buffer diagnostics | trouble | `git.lua` |
| `<leader>xs` / `<leader>xl` | symbols / LSP defs+refs | trouble | `git.lua` |
| `<leader>xL` / `<leader>xQ` | loclist / quickfix | trouble | `git.lua` |
| `<leader>ac` | toggle Claude terminal | claudecode | `ai.lua` |
| `<leader>ab` / `<leader>as` | add buffer / send selection (v) to context | claudecode | `ai.lua` |
| `<leader>aa` / `<leader>ad` | accept / deny diff | claudecode | `ai.lua` |
| `<leader>ai` | re-register for `/ide` discovery | claudecode | `ai.lua` |

**blink.cmp** (`coding.lua`, `default` preset): `<C-Space>` complete · `<CR>` accept · `<Tab>`/`<S-Tab>`
nav or snippet jump · `<C-e>` hide · `<C-p>`/`<C-n>` prev/next.

## nvim — LSP (on attach)

nvim 0.11 built-in defaults; `gd`/`gD` added in `.config/nvim/lua/plugins/lsp.lua`.

| Key | Action |
|---|---|
| `gd` / `gD` | definition / declaration |
| `K` | hover |
| `grr` · `gri` · `grn` · `gra` | references · implementation · rename · code action |
| `gO` | document symbols |
| `[d` / `]d` | prev / next diagnostic |
| `<C-s>` | signature help (insert) |

---

## tmux

`.tmux.conf`. Prefix = `C-Space`. fzf/popup pickers are backed by `scripts/tmux-*.sh`.
`‹pfx›` below means "press prefix, then the key".

**Panes** (colemak-dh):

| Key | Action |
|---|---|
| `‹pfx›m` `‹pfx›n` `‹pfx›e` `‹pfx›i` | select pane left / down / up / right |
| `‹pfx›M` `‹pfx›N` `‹pfx›E` `‹pfx›I` | resize pane left / down / up / right (5 cells) |
| `‹pfx›\` / `‹pfx›-` | split vertical / horizontal (inherit cwd) |
| `‹pfx›[` / `‹pfx›]` | push pane backward / forward |
| `‹pfx›0` | even-horizontal layout |
| `‹pfx›p` / `‹pfx›P` | show pane numbers / last pane |
| `‹pfx›x` | kill pane (menu) |
| `‹pfx›@` | join pane into an fzf-picked window |

**Copy-mode** (`copy-mode-vi`, mirrors the nvim swap):

| Key | Action |
|---|---|
| `m` `n` `e` `i` | cursor left / down / up / right |
| `j` / `J` | search repeat forward / backward |
| `k` | next word-end |

**Windows** (lowercase = window):

| Key | Action |
|---|---|
| `‹pfx›c` | new window (+ agent sidebar) |
| `‹pfx›w` / `‹pfx›W` | switch window (fzf) / last window |
| `‹pfx›,` / `‹pfx›.` | previous / next window |
| `‹pfx›<` / `‹pfx›>` | push window backward / forward |
| `‹pfx›r` / `‹pfx›k` | rename / kill window (popup / menu) |
| `‹pfx›Tab` | last window |

**Sessions** (uppercase = session):

| Key | Action |
|---|---|
| `‹pfx›s` / `‹pfx›S` | switch session (fzf) / last session |
| `‹pfx›C` | new / switch session (popup) |
| `‹pfx›R` / `‹pfx›K` | rename / kill session (popup / menu) |
| `‹pfx›BTab` | last session |

**Agents / misc:**

| Key | Action |
|---|---|
| `‹pfx›a` / `‹pfx›A` | agent picker (fzf) / toggle agent sidebar |
| `‹pfx›f` | fuzzy-grep scrollback across panes → jump |
| `‹pfx›y` | toggle synchronize-panes |
| `‹pfx›C-r` | reload `~/.tmux.conf` |

---

## AeroSpace

`.config/aerospace/aerospace.toml`. Modifier = `alt`. Focus binds shell out to
`.config/aerospace/aerospace-focus.sh` for spatial cross-monitor focus with wrap-around.

| Key | Action |
|---|---|
| `alt-m` `alt-n` `alt-e` `alt-i` | focus window left / down / up / right |
| `alt-shift-m` `alt-shift-n` `alt-shift-e` `alt-shift-i` | join-with left / down / up / right |
| `alt-←` `alt-↓` `alt-↑` `alt-→` | move window (arrows; layout-neutral) |
| `alt--` / `alt-=` | resize smart −100 / +100 |
| `alt-1`…`alt-9` | focus workspace 1–9 |
| `alt-shift-1`…`alt-shift-9` | move window to workspace 1–9 |
| `alt-/` / `alt-,` | layout tiles / accordion |
| `alt-0` | flatten workspace tree |
| `alt-f` | fullscreen |
| `alt-r` | reload config |
