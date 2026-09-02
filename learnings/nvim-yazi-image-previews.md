# Neovim & Yazi image / document previews on Ghostty (+ tmux)

_2026-08-25_

Getting inline image / PDF / markdown previews working in Neovim (snacks.image) and
Yazi under Ghostty — and especially inside tmux — took several non-obvious fixes.
Captured here so it isn't re-derived from scratch.

> **Using herdr instead of tmux?** nvim (snacks.image) images do **not** render under herdr,
> though `icat`/yazi do. It's a renderer/protocol gap, not a config bug — see §6 for the
> what-works-where matrix and why.

## TL;DR — what it takes

**CLI tools** (`Brewfile`): `chafa` (image fallback renderer), `poppler` (`pdftoppm`, PDF),
`ghostscript` (`gs`, PDF in nvim), `imagemagick`, `resvg` (SVG), `jq` (JSON in yazi),
`sevenzip` (archives), `glow` (markdown in yazi), `tectonic` (LaTeX math in nvim). Plus
`mmdc` (`@mermaid-js/mermaid-cli`, via npm in `setup.sh`) and the `latex` Treesitter parser.

**tmux** (`.tmux.conf`): `allow-passthrough on` + a full `tmux kill-server` restart is what
actually makes Ghostty's kitty graphics flow through tmux. `update-environment TERM` /
`TERM_PROGRAM` are set per yazi's docs, but see gotcha #3.

**Neovim** (`init.lua`, snacks spec `init`):
- `vim.env.SNACKS_GHOSTTY = "1"`, guarded on `GHOSTTY_RESOURCES_DIR` — forces ghostty detection.
- `BufEnter` auto-`:edit` reload for `image` buffers, plus `<leader>ri` to re-render manually.

## Root causes (in the order we hit them)

### 1. Previews showed raw binary / "failed to spawn chafa" / "pdftoppm not found"
Missing CLI tools. Yazi shells out to `chafa`/`pdftoppm`; snacks.image needs
`magick`/`gs`/`tectonic`/`mmdc`. Installing them cleared the errors.
(Note: `/opt/homebrew` writes are blocked in the Claude sandbox, so `brew`/`npm` installs
have to run in the user's own shell.)

### 2. Ghostty's `term = xterm-256color` override breaks TERM-based detection
Ghostty is deliberately set to advertise `xterm-256color` (so SSH to hosts without
`xterm-ghostty` terminfo isn't garbled). Graphics-capability detection that keys off `$TERM`
then can't tell it's Ghostty. Tools differ:
- **Yazi** detects via `$TERM_PROGRAM` → works once that's visible.
- **snacks.image inside tmux** asks tmux for `#{client_termname}` → gets `xterm-256color`
  → strips to `256color` → no match → *"terminal does not support the kitty graphics
  protocol."* Outside tmux it reads the terminal's XTVERSION reply and detects ghostty fine.

Don't "fix" the TERM override — it's load-bearing for SSH. Work around detection instead.

### 3. Inside tmux, `TERM_PROGRAM` is `tmux`, not `ghostty`
tmux sets `TERM_PROGRAM=tmux` for its panes (even with `update-environment TERM_PROGRAM`),
so guarding on `TERM_PROGRAM == "ghostty"` fails inside tmux. **`GHOSTTY_RESOURCES_DIR`
survives into the tmux session env** and is the reliable "am I under ghostty" signal — that's
what the `SNACKS_GHOSTTY` guard keys off. (yazi working after the tmux restart was really
`allow-passthrough` + server restart, not the `update-environment` lines.)

### 4. snacks.image dropped standalone images on a bufferline switch
The big time-sink. Symptom: image shows on open, vanishes when you switch to another
bufferline tab and back; reopening from the file tree restores it.
- **Root cause:** on hide snacks deletes the kitty image (`a=d`); on return it only re-places
  by id (`a=p`) — but the data is gone, so nothing renders. A full buffer reload (`:edit`)
  re-transmits and fixes it. `placement:update()` also early-returns when window geometry is
  unchanged, so it won't re-send on its own.
- **The debugging trap:** "tab" was a **bufferline** (buffers-as-tabs), not nvim
  **tabpages**. Every `TabEnter`-based autocmd tried never fired. The fix is a `BufEnter`
  handler that reloads `image` buffers; `<leader>ri` (manual `:edit`) was the diagnostic that
  proved the reload path works before automating it.

### 5. `ostty 1.3.1` written into markdown/image buffers (file-corrupting)
snacks.image detects the terminal by sending an XTVERSION probe (`\27[>q`) and parsing the
reply (`\eP>|ghostty 1.3.1\e\\`) via a `TermResponse` autocmd. When that autocmd doesn't
capture the reply, the bytes land in the buffer as literal text (`ostty 1.3.1…`) — and it's a
**real edit** that `:w` writes to disk, not a cosmetic artifact. Shows once per session
(detection is cached after the first probe).
- **Root cause:** `.tmux.conf` had `set -g extended-keys always`. snacks only skips the probe
  (querying tmux for the terminal name instead) when `tmux show -g extended-keys` ends in
  ` on` — `always` doesn't match. So snacks sent the probe *thinking* extended-keys were off,
  but they were active, which is exactly the condition (snacks' own comment, issue #2332) that
  breaks `TermResponse` capture → the reply leaks.
- **Fix:** `extended-keys always` → `on` in `.tmux.conf`. snacks then takes its no-probe path,
  so nothing leaks; rendering is unaffected (still forced via `SNACKS_GHOSTTY`). `on` still
  forwards CSI-u to apps that negotiate it (the S-Enter bind is a literal send, unaffected).
- **Dead end — do NOT retry:** pre-seeding `require("snacks.image.terminal")._terminal` in a
  custom snacks `config` to skip the probe **broke image rendering entirely** (even
  `<leader>ri`). Replacing `opts` with a custom `config`, and/or the seed itself, is unsafe.

### 6. Switched multiplexer to herdr → nvim images don't render (but icat does)
After moving the daily driver from tmux to **herdr** (`~/.config/herdr`), standalone/markdown
images stopped rendering in nvim — while `icat`, `kitten icat`, and `chafa -f kitty` still drew
fine in the same herdr pane. This is **not a regression of the tmux setup**: the image feature
was built and tuned under tmux (commit "previews under ghostty + tmux", 2026-08-26) and had
**never** worked under herdr — herdr's `kitty_graphics` defaults to `false`, so herdr wasn't
even attempting graphics until the flag was flipped (uncommitted, added while debugging this).

**What works where** (current state: herdr 0.8.2, `kitty_graphics = true`):

| renderer path | icat / chafa (`a=T` one-shot) | nvim snacks.image (`a=t` store + `a=p` place-by-id) |
|---|---|---|
| Ghostty raw            | ✅ | ✅ |
| tmux (passthrough→Ghostty) | ✅ | ✅ |
| herdr (native re-render)   | ✅ | ❌ |

**Why — it's about who renders and which kitty sub-protocol they implement:**
- Ghostty raw and **tmux with `allow-passthrough on`** both end with **Ghostty** doing the
  drawing — tmux just forwards the raw escapes. Ghostty implements the *full* kitty protocol,
  including the store-image-by-id (`a=t`) + place-by-id (`a=p`) model snacks uses. snacks worked
  under tmux because **Ghostty**, not tmux, rendered it.
- **herdr does not pass through.** Its clients use `render_encoding=SemanticFrame` (visible in
  `herdr-server.log`): herdr re-renders every pane itself and, with `kitty_graphics=true`, paints
  kitty graphics with its *own* implementation. That implementation handles the one-shot
  `a=T` "direct file frames" (what icat/chafa/`kitten icat` emit) but not snacks' store+place.

So the same nvim/snacks config renders or not depending purely on the renderer underneath.

**Confirmed (observed / read from source):**
- icat/chafa render in herdr, snacks does not (tested in-pane).
- chafa emits `_Ga=T,f=32,…` — one-shot transmit-and-display (captured control codes).
- snacks transmits `{ t="f", i=id, f=100 }` → defaults to `a=t` (store by id, no display;
  `image.lua:146`), then places with `a="p"` by id — in **both** the placeholder path
  (`placement.lua:551`) and the fallback path (`render_fallback`, `placement.lua:415`).
- herdr release notes describe only "direct file frames"; no mention of placeholders or
  place-by-id. `render_encoding=SemanticFrame` in the server log = herdr re-renders, not passthrough.

**Speculative / NOT yet confirmed:**
- That herdr's kitty impl *specifically* lacks `a=t`/`a=p` (store+place-by-id) is **inferred**
  from "direct file frames" + snacks failing — herdr logs graphics at INFO level with no
  passthrough/reject trace, so it was never directly observed rejecting the command.
- **Second suspect, unverified:** herdr may report zero cell-pixel geometry to the pane
  (`herdr-server.log` shows `cell_*_px=0` on most client connections; only the newest showed
  `8×18`). snacks sizes images from pixel geometry and renders nothing if it's `0` — this could
  be the real (or a compounding) blocker. Decisive check never captured: in the failing nvim,
  `:checkhealth snacks` (image section) + `:lua =require("snacks.image.terminal").size()`.
  Run those before filing a herdr issue to say precisely which gap it is.

**Tried and reverted (do NOT re-attempt without new info):**
- Forcing `placeholders = false` for the ghostty env under herdr (`vim.env.HERDR_ENV == "1"`,
  mutating `require("snacks.image.terminal").envs()` in the snacks `init`). This routes snacks to
  its direct-placement fallback, but that fallback *still* places by id (`a=p`), so it's
  **insufficient** — images stayed blank (confirmed: `env().placeholders` read `false`, still
  nothing). It also degrades bare-ghostty (markdown inline → floating window, since `doc.inline`
  gates on `env().placeholders`). Reverted. Only worth revisiting if herdr adds place-by-id AND
  still lacks unicode placeholders.
- `edit` → `edit!` in the `<leader>ri` keymap and `BufEnter` reload, to swallow the E37 from the
  probe leak. Reverted too: the E37 is a herdr-only artifact (§5's `extended-keys` fix means no
  leak under tmux, and bare ghostty captures the reply cleanly), and images don't render under
  herdr anyway, so `<leader>ri` is moot there. Plain `edit` stays correct for the tmux/ghostty
  paths where images actually work.

**Also unaffected under herdr:** the tmux machinery (§2–§5: `allow-passthrough`, `extended-keys`,
the `client_termname` path) is all gated behind `if vim.env.TMUX` in snacks — none runs under
herdr. Only the `SNACKS_GHOSTTY` guard (fires via `GHOSTTY_RESOURCES_DIR`) and the `BufEnter`
reload still apply.

**Practical workaround:** for inline nvim image/PDF/math previews, use a tmux pane or bare
Ghostty; inside herdr, use `icat`/yazi for quick viewing until herdr's kitty graphics gains
place-by-id (and non-zero pane pixel geometry).

## Debugging lessons

- **Disambiguate "tab" immediately**: bufferline (buffers → `BufEnter`) vs tabpages
  (`TabEnter`) are different events. Assuming tabpages cost ~4 failed iterations.
- **Terminal graphics can't be tested headless** (no TUI/graphics in the sandbox), so blind
  timing hacks (`vim.schedule`, `defer_fn(150/300ms)`, `SafeState`) each burned a real test
  cycle. Get the decisive datapoint (which event fires, where focus lands) *before* iterating.
- Prefer detecting Ghostty via `GHOSTTY_RESOURCES_DIR` over `TERM`/`TERM_PROGRAM` whenever
  tmux might be in the path.
- Third-party yazi plugins lag the API: `glow.yazi` still used the pre-26.x plugin API
  (`:args`, `ya.mgr_emit`, `ui.Text.parse`); it had to be rewritten against yazi's own preset
  `json.lua` (`:arg`, `ya.emit`, `ya.preview_widget`, `ui.lines`).

## Where the fixes live

- `Brewfile` — the preview CLI tools.
- `scripts/setup.sh` — `mmdc` via npm.
- `scripts/refresh-linux-vendored.sh` — vendored `glow` binary for the linux box.
- `.config/yazi/{yazi.toml, package.toml, plugins/glow.yazi/}` — markdown preview (glow plugin
  patched for the yazi 26.x API).
- `.tmux.conf` — `allow-passthrough on`, `update-environment TERM`/`TERM_PROGRAM`.
- `.config/nvim/lua/plugins/ui.lua` — snacks `image` enabled, the `SNACKS_GHOSTTY` guard, the
  herdr `placeholders=false` override (§6), the `BufEnter` reload, and `<leader>ri` (uses
  `:edit!`). (`render-markdown.nvim` / `latex` parser live in their own `lua/plugins/*` files
  since the config was split into the lazy.nvim layout.)
