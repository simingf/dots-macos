# FRAGILE.md — brittle spots in this nvim config

Places that reach into plugin **internals** or **vendored upstream files** instead of a
documented `opts` / `keys` / public API. A plugin update can break them, usually
**silently** (they're guarded to no-op, not error).

`lua/config/healthcheck.lua` checks the startup-visible assumptions and warns once after
`VeryLazy` if one broke; `:ConfigHealth` prints the full report. **After `:Lazy update` /
`:Lazy sync`, watch for that warning.**

> Mac-only doc (like `THEME.md`); the code it describes, `healthcheck.lua` included, is
> byte-identical across `dots-{macos,linux,windows}`.

---

## 🔴 High — undocumented internals, fast-moving upstreams

### snacks explorer internals — `lua/plugins/navigation.lua`
- Picker instance fields: `Snacks.picker.get({source="explorer"})[1]`, `p.list.win.win`,
  `p.list.win:valid()`, **`p.layout.root.win`**, `p.input` / `p.preview`, `p:current()`,
  `p:action("tab_open")`, `p:selected()`, `p.list:set_selected()`, `p:update_titles()`,
  `p.opts.wrap`, `p:is_focused()` / `p:focus("list")` (`<leader>o`).
- Private modules: `snacks.explorer.git.refresh` + `snacks.explorer.actions.update` (`R`,
  FocusGained; busts git.lua's `CACHE_TTL`), `snacks.explorer.actions.actions.confirm` and
  `picker.input.filter.meta.searching` (`tab_open`).
- The 24/40 width toggle resizes the hidden root split the list float is derived from.
- **Failure mode:** silent no-op (the `if not p … return` guards) — `o` / `y` / `W` / `R` /
  width toggle quietly stop.
- **Health check covers:** `picker.get`, `picker.util.path`, `explorer`, `explorer.reveal`,
  `bufdelete`. Not instance fields or the private modules — suspect those first.

### explorer layout / zen detection — `lua/config/nav.lua`, `lua/config/keymaps.lua`
The docked explorer box is found by filetype **`snacks_layout_box`** (snacks `layout.lua`)
in `nav.lua` `tree_box()` and keymaps.lua `keep_column()`; `<leader>z` zoom by
`Snacks.zen.win`.
- **Failure mode:** split nav treats the tree as floats (wincmd skips past it), `<leader>M/I`
  rebalance squeezes the explorer, nav ignores a zoom.
- Not health-checked.

### snacks explorer cursor for the lazygit sidebar — `lua/config/tmux_lazygit.lua`
Reads the tree row via `p:current()` + `Snacks.picker.util.path(item)` / `item.dir`, and
detects "tree focused" by filetype **`snacks_picker_list`** (snacks `picker/core/list.lua`).
- **Failure mode:** moving through the tree stops switching the `prefix g` sidebar (file
  buffers still drive it).
- **Health check covers:** `picker.get` / `picker.util.path`; not the filetype.

### snacks image patches — `lua/plugins/ui.lua`
The snacks `config` monkey-patches `snacks.image.placement` (`update`, `error`, `state`),
`snacks.image.convert.convert`, the private `Convert` class (fetched as an upvalue of
`convert`; `resolve` / `_resolve` / `ft`), and `snacks.image.image.new`; uses `util.dim` and
`terminal.size`.
- **Failure mode:** standalone images go blank after leaving the window, show "Image
  Conversion Failed" without magick, don't fill the window, keep stale pixels after an
  overwrite, or big PNGs go out full size.
- **Health check covers:** those functions existing, and `Convert._resolve` / `ft`.

### bufferline Tabpage wrap — `lua/plugins/ui.lua`
bufferline's renderer (`ui.lua` `add_suffix`) shows a tab's ✕ **or** its ● (unsaved). The
`config` wraps internal `require("bufferline.models").Tabpage.new`: on `t.modified` it clears
it and puts ● on `t.icon` (`BufferLineModifiedSelected`), so ✕ stays and closing asks to save
(`config/tabs.lua` `settle_unsaved`).
- **Failure mode:** `Tabpage` / `new` moved → setup errors; fields renamed (`modified`,
  `icon`, `icon_highlight`) → unsaved tabs silently go back to ● with no ✕.
- **Health check covers:** `bufferline.models.Tabpage.new` exists.

### nvim-treesitter `main` branch — `lua/plugins/treesitter.lua`
Both `nvim-treesitter` and `-textobjects` track the unstable `main` rewrite:
`require("nvim-treesitter").install(...)`, manual `select_textobject` wiring, `@local.scope`
in group `"locals"`. `main`'s `setup()` silently drops unknown fields.
- **Failure mode:** an update breaks parser install or the `af`/`lf`/`ac`/`lc`/`as`
  textobjects. Pinned in `lazy-lock.json`, so only on an explicit update.
- **Health check covers:** `nvim-treesitter.install` and
  `textobjects.select.select_textobject` being functions.

---

## 🟡 Medium — vendored files / third-party sources

### markdown-preview bundled CSS — `lua/plugins/treesitter.lua`
Reads the plugin's bundled `app/_static/markdown.css` by hardcoded `stdpath("data")` path and
appends overrides that depend on the `#page-ctn` id (capped in `page.css`) and
github-markdown CSS variable names.
- **Failure mode:** file moved → base CSS becomes `""` (GitHub typography lost, overrides
  remain); `#page-ctn` renamed → width override silently stops.
- **Health check covers:** the bundled `markdown.css` existing (skipped over SSH).

### roslyn third-party mason registry — `lua/plugins/lsp.lua`
C# LSP needs `github:Crashdummyy/mason-registry` to keep shipping a `roslyn` package
(gated on `HAS_DOTNET`).
- **Failure mode:** registry gone / renamed → roslyn install fails.
- Not health-checked (would need a mason registry query).

### mason-lspconfig v2 auto-enable — `lua/plugins/lsp.lua`
Relies on nvim 0.11 `vim.lsp.config` / `vim.lsp.enable` + mason-lspconfig v2
`automatic_enable` (v1→v2 already broke this once).
- **Failure mode:** a future major shifts the enable flow → servers don't start.
- Not health-checked (behavioral).

---

## 🟢 Low — cosmetic, degrades gracefully

### bufferline highlight-key list — `lua/plugins/ui.lua`
Hardcoded list of bufferline highlight groups whose bg is flattened. New / renamed groups
just aren't flattened → a stray shade, never an error.

### snacks hl-group names + `SNACKS_GHOSTTY` — `lua/plugins/ui.lua`
`SnacksPicker{,List,Input,Box,Directory,Link,LinkBroken}` (LS_COLORS mirror) and the
`SNACKS_GHOSTTY` env escape hatch for image detection. Renamed → theming or image detection
silently no-ops.

---

## Adding a fragile spot

Add an entry here and, if the assumption is a startup-checkable symbol / file, a check in
`lua/config/healthcheck.lua`.
