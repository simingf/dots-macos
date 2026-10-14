# KEYBINDS.md — keybind registry

One directional schema everywhere: **Colemak-DH `mnei`** in place of `hjkl`. This registers
every keybind across the systems that share that schema (nvim, tmux, AeroSpace) so a new
binding can be matched to the rest — plus the **⌘ shortcuts** shared by zsh, nvim and Claude Code
([below](#-shortcuts--mouse-zsh--nvim--claude-code)). Theming has a sibling registry in [`THEME.md`](./THEME.md).

## The schema

`hjkl` is replaced by **`mnei`** for every directional action, in every system:

| Key | Direction | Why not `hjkl` |
|---|---|---|
| `m` | ← left | `h`/`H` are claimed by arrow.nvim (nvim); `m` is the reachable stand-in |
| `n` | ↓ down | `n`/`e`/`i` sit on the Colemak-DH home row (QWERTY `j`/`k`/`l` positions) |
| `e` | ↑ up | |
| `i` | → right | |

Each pair swaps (`m`↔`h`, `n`↔`j`, `e`↔`k`, `i`↔`l`), so a displaced key's job moves to its partner —
consistently in **both nvim and tmux copy-mode**:

- **`j` / `J`** → repeat search forward / backward (took over from `n`/`N`).
- **`k`** → word-end motion (took over from `e`).
- **`l`** → insert, and the inner-text-object prefix (took over from `i`; nvim only).

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

¹ `i`↔`l` is swapped in **every** mode (normal / visual / operator-pending), so inner text objects
use `l`: `dlw`, `cl"`, `yl(`, `vlw`, treesitter `dlf`/`vlc`. `a` objects are unchanged (`daw`, `daf`).
No visual/operator-pending map may start with `i`, or every `i` there would wait out `timeoutlen`.
AeroSpace **move-window** stays on `alt-arrows` (layout-neutral, so no letter to remap).

---

## nvim — core

`.config/nvim/lua/config/keymaps.lua`. Leader = `Space`.

| Key | Action | Mode |
|---|---|---|
| `m` `n` `e` | left / down / up (→ `h` `j` `k`) | n, x, o |
| `i` | right (→ `l`) | n, x, o |
| `l` | insert (n) · inner-text-object prefix (x, o) (→ `i`) | n, x, o |
| `j` / `J` | search repeat forward / backward (→ `n` / `N`) | n, x |
| `*` / `#` | search the word under the cursor forward / backward | n |
| `k` | word-end (→ `e`) | n, x, o |
| `<leader>m` `<leader>n` `<leader>e` `<leader>i` | focus window left / down / up / right | n |
| `<leader>\` | vertical split | n |
| `<leader>-` | horizontal split | n |
| `<leader>j` | join lines (rehomed from `J`; `gJ` still joins w/o space) | n, x |
| `0` / `L` | line start (`^`) / line end (`$`) | n, x, o |
| `x` / `X` | delete char / line to black-hole register | n, x |
| `gy` / `gp` | yank to / paste from system clipboard | n,x / n |
| `<leader>f` | format buffer (conform → LSP fallback) | n, x |
| `<C-a>` / `<C-e>` | line start / end, like zsh | i |

Also `:FormatDisable[!]` / `:FormatEnable` toggle format-on-save (buffer / global).

**Search highlights auto-clear:** `hlsearch` is on only while the last normal-mode key was a search
key (`/` `?` ⌘F `j` `J` `*` `#`); any other key turns it off (`vim.on_key` in `keymaps.lua`).

**Disabled on purpose** (accident-prone or unused — deleted / `<Nop>`'d in `keymaps.lua`):
`<C-a>`/`<C-x>` (±1 the number; n, x) · `<C-z>` (suspend) · `ZZ` / `ZQ` (quit) · `gQ` (Ex mode) ·
`&` (repeat `:s`) · `[`/`]` list pairs for arglist / tags / loclist / quickfix / buffers
(`[a ]a [A ]A [t ]t [T ]T [⌃T ]⌃T [l ]l [L ]L [⌃L ]⌃L [q ]q [Q ]Q [⌃Q ]⌃Q [b ]b [B ]B`) · syntax-node
selection (`an` `in` · `[n ]n [N ]N`) · matchit extras (`g%` `[%` `]%` `a%`; plain `%` stays) ·
nvim-recorder's `yq` / `##` (`editor.lua`).

## nvim — plugins

All under `.config/nvim/lua/plugins/`.

| Key | Action | Plugin | File |
|---|---|---|---|
| `<leader><leader>` | buffer-local keymap hints | which-key | `ui.lua` |
| `<leader>w` · `<leader>x` · `<leader>t` · `<leader>b` | groups: windows · trouble · pickers · buffer | which-key | `ui.lua` |
| `<leader>bi` / `<leader>bm` | next / prev buffer | bufferline | `ui.lua` |
| `<leader>bp` | pick buffer (jump by letter) | bufferline | `ui.lua` |
| `<leader>bc` | close buffer | snacks.bufdelete | `ui.lua` |
| `<leader>tt` | fuzzy find in buffer | snacks.picker | `ui.lua` |
| `<leader>tg` | live grep | snacks.picker | `ui.lua` |
| `<leader>tb` | buffers | snacks.picker | `ui.lua` |
| `<leader>tf` | find files | snacks.picker | `ui.lua` |
| `<leader>tr` | recent files | snacks.picker | `ui.lua` |
| `<leader>td` | diagnostics | snacks.picker | `ui.lua` |
| `<leader>tn` | notifications | snacks.picker | `ui.lua` |
| `<leader>ty` | yank-ring history | yanky | `editor.lua` |
| `s` / `S` | flash jump / treesitter jump | flash | `editor.lua` |
| `H` / `h` | bookmark: global / buffer leader | arrow.nvim | `editor.lua` |
| `q` `Q` `<C-q>` `cq` `dq` | macro: rec · play · switch slot (3: a/b/c) · edit · delete-all | recorder | `editor.lua` |
| `<leader>\`` | reveal / leave file tree | snacks.explorer | `navigation.lua` |
| `<leader>y` / `<leader>Y` | yazi @ current file / cwd | yazi.nvim | `navigation.lua` |
| `<leader>p` | markdown preview toggle | markdown-preview | `treesitter.lua` |
| `af`/`lf` · `ac`/`lc` · `as` | text-objects: function · class · scope (inner = `l`, see ¹) | ts-textobjects | `treesitter.lua` (x, o) |
| `<leader>xx` / `<leader>xs` | diagnostics / symbols | trouble | `git.lua` |

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
| `[d` / `]d` · `[D` / `]D` | prev / next · first / last diagnostic |
| `<C-s>` | signature help (insert) |

---

## ⌘ shortcuts + mouse (zsh · nvim · Claude Code)

Ghostty (`.config/ghostty/config`, Mac-only) sends each ⌘ shortcut as a private sequence
`\e[9001~`…`\e[9015~`; `.tmux.conf` maps them to `User0`–`User14`, which call
`scripts/tmux-cmdkey.sh` to give the active pane its own action. Plain bytes end to end, so they
work in the Linux box's tmux over ssh too. zsh widgets: `.config/zsh/30-interactive.zsh`; nvim
`<D-…>` maps: `…/lua/config/keymaps.lua`. ⌘V is ghostty's own paste everywhere.

| Key | zsh | nvim | Claude Code |
|---|---|---|---|
| ⌘A | select the line | select all | — |
| ⌘C / ⌘X | copy / cut selection (OSC 52) | copy / cut selection | — (drag copies) |
| ⌘Z / ⇧⌘Z | undo / redo | undo / redo | undo / — (no redo) |
| ⌘← / ⌘→ | line start / end | line start / end | line start / end |
| ⌘⌫ | delete the line | delete line (`dd`) · insert: to line start · visual: selection | delete to line start |
| ⇧⌘⌫ | delete the whole command | — | clear input (Esc Esc; only while idle) |
| ⌘S | — | write buffer | — |
| ⌘F | search scrollback (tmux copy-mode; `j`/`J` next/prev) | `/` | — |
| ⌘P | — | file picker | — |
| ⌘/ | — | toggle comment | — |
| ⌘] / ⌘[ | — | indent / outdent | — |
| ⇧← / ⇧→ | select | select (`keymodel`) | — |

In a tmux copy-mode pane, ⌘C / ⌘X copy the selection and ⌘F searches again.

**Mouse:**

| Action | zsh | nvim | Claude Code |
|---|---|---|---|
| Click | move the cursor (tmux `MouseUp1Pane` → `@click`) | move the cursor | move the cursor |
| Drag | copy + clear on release (tmux) | copy on release, stays selected | copy + clear on release (tmux takes the drag) |

While a zsh selection is up, typing / pasting replaces it and ⌫ deletes it.

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
| ⌘C / ⌘X · ⌘F | copy selection · search again (see [⌘ shortcuts](#-shortcuts--mouse-zsh--nvim--claude-code)) |

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

`.config/aerospace/aerospace.toml`. Modifier = `alt`. Focus wraps around within the workspace.

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
