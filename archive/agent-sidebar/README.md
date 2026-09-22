# Archived: agent sidebar

The clickable, live-updating **agent sidebar** — a fixed-width left split (`prefix A` to toggle) that
showed a session/window tree plus a flat agent list, each with a colored status dot, and let you
click to jump — was retired in favor of surfacing the same status natively in the **top status bar**
(a per-window colored dot after the tab name; see `_paint` / `@agent_dot` in `scripts/tmux-agents.sh`).

The top bar can't do everything the sidebar did: it only shows the **current session's** tabs (no
cross-session tree), and there's no per-agent task-summary list or click-to-jump (that lives in the
`prefix a` picker popup, which is still active). This folder keeps the sidebar code so it can come back.

## Files

- **`tmux-agents-sidebar.sh`** — the sidebar-only shell functions extracted verbatim from
  `scripts/tmux-agents.sh`: `_sidebar`, `_sidebar_open`, `_panel`, `__lines`, `_activate`, `_sock`,
  `_live_socks`, `_deflect`, `_fix_width`, `_reap`, `_reclaim_layout`, `_csum`, and the `SIDEBAR_COLS`
  constant. **Not runnable standalone** — they call shared helpers still in `tmux-agents.sh`
  (`_statef`, `_focused_pane`, `_jump`, `_agents_status`, `_list`, `$FZF`, `$AGENT_RE`).
- **`tmux.conf.snippet`** — the `.tmux.conf` binds/hooks (and the `dotslg` line) that were removed.

## What stayed behind (drives the top bar now)

- `scripts/tmux-agents.sh`: detection (`_list`/`_sorted`/`_agents_status`/`_statef`), the `pick`/`__fzf`/`_fmt`
  picker, `count`, and the top-bar `_dot`/`_paint`/`_refresh`/`_refresh_agents`/`_mark_read`.
- `.tmux.conf`: the `mark-read` / `refresh` / `refresh-agents` hooks and the `#{E:@agent_dot}` in
  `window-status-format`.

## To restore

1. Merge the functions from `tmux-agents-sidebar.sh` back into `scripts/tmux-agents.sh`, and re-add their
   dispatch cases: `sidebar`, `sidebar-open`, `panel`, `__lines`, `activate`, `deflect`, `fix-width`, `reap`,
   `__reclaim`.
2. Put the `_deflect` call back at the top of `_mark_read`, and restore the fzf-socket live-reload tail of
   `_refresh` (the `curl … reload-sync` block that pushes `__lines` into each sidebar's `--listen` socket).
3. Add the binds/hooks from `tmux.conf.snippet` to `.tmux.conf`, and the `sidebar-open` line back into
   `dotslg` in `.config/zsh/60-functions.zsh`.
4. `stow` is unaffected (same files). Re-sync to Linux with `scripts/sync-dotfiles.py --apply`, then
   `tmux kill-server` (or `source-file` + reopen) to pick up the restored binds.

The full pre-retirement version of both files is also recoverable from git history.
