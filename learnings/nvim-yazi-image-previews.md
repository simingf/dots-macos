# Neovim & Yazi image / document previews on Ghostty (+ tmux)

_2026-08-25_

Getting inline image / PDF / markdown previews working in Neovim (snacks.image) and
Yazi under Ghostty — and especially inside tmux — took several non-obvious fixes.
Captured here so it isn't re-derived from scratch.

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
- `.config/nvim/init.lua` — snacks `image` enabled, `render-markdown.nvim`, `latex` parser,
  the `SNACKS_GHOSTTY` guard, the `BufEnter` reload, and `<leader>ri`.
