#!/usr/bin/env python3
"""Sync dots-linux and dots-windows from dots-macos (the source of truth).

Only handles byte-identical files. Anything that intentionally diverges
(.zshrc, .gitconfig, etc.) is described in CLAUDE.md and edited by hand.

Usage:
  scripts/sync-dotfiles.py               # default: report drift, no writes
  scripts/sync-dotfiles.py --apply       # copy drifted files
  scripts/sync-dotfiles.py --apply linux # only sync one target

Idempotent: re-running with no drift is a no-op.
"""

from __future__ import annotations

import argparse
import filecmp
import shutil
import sys
from pathlib import Path

HOME = Path.home()
SRC = HOME / "dots-macos"

# (mac-relpath, target-relpath)
IDENTICAL: dict[str, list[tuple[str, str]]] = {
    "linux": [
        (".tmux.conf", ".tmux.conf"),
        (".config/nvim/init.lua", ".config/nvim/init.lua"),
        (".config/nvim/lazy-lock.json", ".config/nvim/lazy-lock.json"),
        ("scripts/tmux-fzf-sessions.sh", "scripts/tmux-fzf-sessions.sh"),
        ("scripts/tmux-fzf-windows.sh", "scripts/tmux-fzf-windows.sh"),
        (".config/yazi/yazi.toml", ".config/yazi/yazi.toml"),
        (".config/yazi/keymap.toml", ".config/yazi/keymap.toml"),
        (".config/yazi/theme.toml", ".config/yazi/theme.toml"),
        (".config/yazi/flavors/rose-pine.yazi/flavor.toml", ".config/yazi/flavors/rose-pine.yazi/flavor.toml"),
        (".config/yazi/flavors/rose-pine.yazi/tmtheme.xml", ".config/yazi/flavors/rose-pine.yazi/tmtheme.xml"),
        (".claude/CLAUDE.md", ".claude/CLAUDE.md"),
    ],
    "windows": [
        (".config/nvim/init.lua", "AppData/Local/nvim/init.lua"),
        (".config/nvim/lazy-lock.json", "AppData/Local/nvim/lazy-lock.json"),
        ("Library/Application Support/lazygit/config.yml", "AppData/Roaming/lazygit/config.yml"),
        ("Library/Application Support/Code/User/settings.json", "AppData/Roaming/Code/User/settings.json"),
        ("Library/Application Support/Code/User/keybindings.json", "AppData/Roaming/Code/User/keybindings.json"),
        (".config/ohmyposh/zen.toml", "ohmyposh/zen.toml"),
        (".config/ripgrep/rg.conf", "ripgrep/rg.conf"),
        (".config/gh/config.yml", "AppData/Roaming/GitHub CLI/config.yml"),
        (".claude/CLAUDE.md", ".claude/CLAUDE.md"),
    ],
}

TARGETS = {"linux": HOME / "dots-linux", "windows": HOME / "dots-windows"}


def files_equal(a: Path, b: Path) -> bool:
    if not a.exists() or not b.exists():
        return False
    return filecmp.cmp(a, b, shallow=False)


def sync_target(name: str, target: Path, apply: bool) -> int:
    print(f"\n== {name}  ({target})")
    if not target.exists():
        print(f"   skipped: target dir does not exist")
        return 0

    drift = 0
    for src_rel, dst_rel in IDENTICAL[name]:
        src, dst = SRC / src_rel, target / dst_rel
        if not src.exists():
            print(f"   ! source missing: {src_rel}")
            continue
        if files_equal(src, dst):
            continue
        drift += 1
        action = "copy" if apply else "would copy"
        print(f"   {action}  {src_rel} -> {dst_rel}")
        if apply:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    if drift == 0 and apply:
        print("   in sync")
    return drift


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--apply", action="store_true",
                   help="copy drifted files; default is dry-run/check")
    p.add_argument("targets", nargs="*", choices=list(TARGETS),
                   help="restrict to a subset (default: all)")
    args = p.parse_args()

    if not SRC.exists():
        print(f"source not found: {SRC}", file=sys.stderr)
        return 2

    selected = args.targets if args.targets else list(TARGETS)
    total = 0
    for name in selected:
        total += sync_target(name, TARGETS[name], args.apply)

    if not args.apply and total:
        print(f"\n{total} drift(s). Re-run with --apply to copy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
