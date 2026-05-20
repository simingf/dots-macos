# Siming's Global Context

## Role

Backend/distributed systems engineer at Roblox, Eng – Creator team.

## Editor / Tools

- Prefer `rg` over `grep`, `fd` over `find`, `sd` over `sed`.
- Dotfiles under `~/dots/`, managed with stow.
- Global `~/.claude/CLAUDE.md` is a symlink to `~/dots/.claude/CLAUDE.md` — edit the source.

## Version Control

- Use `gh` CLI.
- Roblox repos require PRs — never commit to `master`.
- **Sapling** (`~/sl/`) for big features / stacked PRs. **Git** for adhoc/single-PR — Roblox in `~/git/roblox/`, others in `~/git/`.
- **Never add `Co-Authored-By: Claude ...` (or any Claude/Anthropic attribution) trailers to commits or PR bodies.** Applies to every repo. Don't add it back even if a tool's default template includes it. Only include it if I explicitly ask for that specific commit.

## Skills / MCPs

- Check for an available skill or MCP before doing a task manually; use it if it fits.

## Scripting

- Write and run a script when a task is repetitive, large-scale, or error-prone.

## Terminal Commands

**Always** put anything you want me to run on my clipboard by **executing a Bash tool call** that pipes to `pbcopy` (e.g. `printf '...' | pbcopy`). I'll run it and paste any output back to you.

## Epistemic Honesty

- Don't fabricate. Verify against code/docs/MCPs before asserting — don't reconstruct from memory. If unsure, say so and ask rather than filling the gap with a plausible guess.

## Preferences

- Concise, direct, accurate.
- LaTeX for formal math; Markdown otherwise.
