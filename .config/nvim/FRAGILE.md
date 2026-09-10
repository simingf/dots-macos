# FRAGILE.md — brittle spots in this nvim config

Places that reach into plugin **internals** or **vendored upstream files** instead of a
documented `opts` / `keys` / public-API surface. They work today but can break on a plugin
update — and usually **silently**, because they're guarded to no-op rather than error. So a
feature quietly stops working instead of throwing a stacktrace.

`lua/config/healthcheck.lua` validates the load-bearing *module/API* assumptions on startup
and warns (once, on `VeryLazy`) if one broke. Run `:ConfigHealth` for the full report
(healthy checks included). **After a `:Lazy update` / `:Lazy sync`, watch for that warning.**

> Mac-only doc (like `THEME.md`). The code it describes is byte-identical across
> `dots-{macos,linux,windows}`, and `healthcheck.lua` syncs with it — only this write-up
> stays on the Mac control plane.

---

## 🔴 High — undocumented internals, fast-moving upstreams

### snacks explorer internals — `lua/plugins/navigation.lua`
The explorer `keys` handlers (`o`, `y`, `W`) and the width-toggle `WinEnter` autocmd reach
deep into snacks' private picker structure: `Snacks.picker.get({source="explorer"})[1]`,
`p.list.win.win`, `p.list.win:valid()`, **`p.layout.root.win`**, `p.input`/`p.preview`,
`p:current()`, `p:action("confirm")`, `p:selected()`, `Snacks.picker.util.path()`,
`p.list:set_selected()`, `p:update_titles()`, `p.opts.wrap`, plus `p:is_focused()` in the
`<leader>`` reveal. The width toggle specifically exploits *how snacks derives the visible
float from a hidden root split* — pure implementation detail.
- **Failure mode:** silent no-op — the `if not p … return` guards swallow it, so the
  explorer still works but `o` / `y` / `W` / the width-expand quietly stop.
- **Health check covers:** the module-level API (`picker.get`, `picker.util.path`,
  `explorer`, `explorer.reveal`, `bufdelete`). It **cannot** check the instance fields
  (`p.list.win.win`, `p.layout.root.win`) — those need a live open picker, so they remain
  silent-fail. If the explorer misbehaves after an update, suspect these first.

### nvim-treesitter `main` branch — `lua/plugins/treesitter.lua`
Both `nvim-treesitter` and `-textobjects` track the in-development `main` rewrite:
`require("nvim-treesitter").install(...)`, the manual `select_textobject` wiring, and
`@local.scope` in group `"locals"`. `main`'s `setup()` silently drops unknown fields.
- **Failure mode:** `main` is explicitly unstable — a sync can change `install()` /
  `select_textobject` signatures and break parser install or the `af`/`ac`/`as` textobjects.
  The commit is pinned in `lazy-lock.json`, so breakage only lands on an explicit update.
- **Health check covers:** `nvim-treesitter.install` and `textobjects.select.select_textobject`
  still being functions.

### claudecode lockfile internals — `lua/plugins/ai.lua`
The `/ide`-rediscovery fs-watch uses `require("claudecode.lockfile")`, `lockfile.lock_dir`,
`lockfile.create`, `cc.state.port`, `cc.state.auth_token` — all undocumented internals of a
young plugin.
- **Failure mode:** a `cc.state` reshape or lockfile-module rename → the watcher errors or
  stops and `/ide` discovery silently breaks again (the exact bug it works around).
- **Health check covers:** `claudecode.lockfile` require-ability + `{lock_dir, create}`.

---

## 🟡 Medium — vendored files / third-party sources

### markdown-preview bundled CSS — `lua/plugins/treesitter.lua`
The mkdp `config` reads the plugin's *bundled* `app/_static/markdown.css` by hardcoded
`stdpath("data")` path, appends the rose-pine overrides, and depends on the `#page-ctn`
container id and the github-markdown CSS-variable names.
- **Failure mode:** if mkdp restructures `app/` or renames the file, `io.open` fails → base
  CSS becomes `""`, silently losing GitHub typography (only the overrides remain); the
  `#page-ctn` width hack also breaks quietly if that id is renamed.
- **Health check covers:** the bundled `markdown.css` still being present.

### roslyn third-party mason registry — `lua/plugins/lsp.lua`
C# LSP depends on `github:Crashdummyy/mason-registry` existing and still shipping a `roslyn`
package (mac-only, gated on `HAS_DOTNET`).
- **Failure mode:** the external registry disappears/renames → roslyn install fails.
- Not health-checked (would need a mason registry query at startup).

### mason-lspconfig v2 auto-enable — `lua/plugins/lsp.lua`
On the nvim 0.11 `vim.lsp.config`/`vim.lsp.enable` API + mason-lspconfig v2 `automatic_enable`
(the v1→v2 change already broke this once).
- **Failure mode:** a future mason-lspconfig major could shift the enable flow again.
- Not health-checked (behavioral, not a missing symbol).

---

## 🟢 Low — cosmetic, degrades gracefully

### bufferline highlight-key list — `lua/plugins/ui.lua`
A hardcoded ~30-entry list of bufferline highlight-group names whose bg is flattened to the
editor bg. New/renamed groups just won't be flattened → a stray shade, never an error.

### snacks hl-group names + `SNACKS_GHOSTTY` — `lua/plugins/ui.lua`
`SnacksPickerDirectory`/`Link`/`Box`/… group names (LS_COLORS mirror) and the
`SNACKS_GHOSTTY` env escape hatch for image detection. If snacks renames them, theming or
image detection silently no-ops (cosmetic).

---

## Adding a fragile spot

If you add code that depends on a plugin internal or a vendored file, add a row here and — if
the assumption is a startup-checkable symbol/file — a check to `lua/config/healthcheck.lua`
so the breakage surfaces loudly instead of silently.
