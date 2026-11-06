#!/usr/bin/env python3
"""test-agent-state.py — offline checks for scripts/tmux-agent-state.py (Mac-only, not synced).

Feeds hand-built Claude Code screens (the shapes herdr's claude.toml rules target, with our status line
below the prompt box) through the ported engine and the publish/hold logic. Run after `update-rules` or any
engine change; a failure prints the screen's `explain` table. To add a case from a live pane:
  tmux capture-pane -p -t <pane>   (and `scripts/tmux-agent-state.py explain <pane>` to see why).
"""

import importlib.util
import io
import os
import sys
from contextlib import redirect_stdout
from pathlib import Path

spec = importlib.util.spec_from_file_location("agent_state", Path(__file__).with_name("tmux-agent-state.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

BOX = """──────────────────────────────── herdr ─
❯
────────────────────────────────
  ~/dots-macos  Opus 5.5  $0.55
  ⏵⏵ bypass permissions on (shift+tab to cycle)"""

# (name, title, screen, expected herdr state, expected winning rule id or None for the idle fallback)
CASES = [
    ("title spinner", "⠂ Fixing tests", "⏺ Working\n\n" + BOX, "working", "osc_title_working"),
    ("title half-circle", "◐ Fixing tests", "", "working", "osc_title_working"),
    ("spinner line, idle title", "✳ herdr",
     "⏺ Running ls\n\n✻ Symbioting… (52s · ↓ 2.6k tokens · thought for 13s)\n  ⎿  Tip: Use /btw\n\n" + BOX,
     "working", "live_turn_working"),
    ("spinner line ✳ frame", "✳ herdr", "✳ Pondering… (3s · ↑ 1k tokens)\n\n" + BOX, "working", "live_turn_working"),
    ("finished turn", "✳ herdr", "⏺ Done.\n\n✻ Worked for 3m 2s\n\n" + BOX, "idle", "live_prompt_box"),
    ("background agents", "✳ herdr", "⏺ Launched\n\n✻ Waiting for 2 background agents to finish\n" + BOX,
     "working", "background_agents_working"),
    ("mcp tasks", "✳ herdr", "✻ Brewed for 1m · 1 MCP task still running\n\n" + BOX,
     "working", "background_mcp_task_working"),
    ("bash permission", "✳ herdr", """⏺ Bash(rm -rf foo)

────────────────────────────────
 Bash command

   rm -rf foo

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for rm commands in /x
   3. No, and tell Claude what to do differently (esc)

 Esc to cancel · Tab to amend · ctrl+e to explain""", "blocked", "bash_permission_prompt"),
    ("ask user question", "✳ herdr", """⏺ Need a decision

────────────────────────────────
 ☐ Approach

 Which approach?

 ❯ 1. A
   2. B

 Enter to select · ↑/↓ to navigate · Esc to cancel""", "blocked", "live_blocked_form"),
    ("dialog words in the transcript", "✳ herdr",
     '⏺ herdr matches "Do you want to proceed?" and "Esc to cancel" in dialogs.\n\n' + BOX,
     "idle", "live_prompt_box"),
    ("transcript viewer", "✳ herdr",
     "⏺ stuff\n\n  Showing detailed transcript · ctrl+o to toggle · ctrl+e to show all", "unknown", "transcript_viewer"),
    ("bare shell", "zsh", "$ ls\nfoo bar\n$ ", "idle", None),
]


def explain(title, screen):
    os.environ["TITLE"] = title
    sys.stdin = io.StringIO(screen)
    buf = io.StringIO()
    with redirect_stdout(buf):
        m.explain(None)
    return buf.getvalue()


def main():
    rules = m.load_rules()
    fails = 0
    try:   # the engine loads claude.json; it must be exactly the vendored toml (needs 3.11+ tomllib)
        if m.RULES_FILE.read_text(encoding="utf-8") != m.toml_to_json(m.RULES_TOML.read_text(encoding="utf-8")):
            fails += 1
            print("FAIL claude.json is stale vs claude.toml — regenerate it (update-rules does)")
    except ModuleNotFoundError:
        print("skip claude.json sync check (no tomllib)")
    for name, title, screen, want_state, want_rule in CASES:
        r = m.detect(rules, screen, title)
        got = (r.state if r else "idle", r.id if r else None)
        if got != (want_state, want_rule):
            fails += 1
            print(f"FAIL {name}: got {got}, want {(want_state, want_rule)}\n{explain(title, screen)}")

    # publish(): working → plain idle is held HOLD_MS; visible idle, skip and unknown behave like herdr.
    idle_plain = None
    visible = next(r for r in rules if r.id == "live_prompt_box")
    skip = next(r for r in rules if r.id == "transcript_viewer")
    checks = [
        ("hold starts", m.publish("working", None, idle_plain, 1000), ("working", 1000)),
        ("hold keeps", m.publish("working", 1000, idle_plain, 1000 + m.HOLD_MS - 1), ("working", 1000)),
        ("hold expires", m.publish("working", 1000, idle_plain, 1000 + m.HOLD_MS), ("idle", None)),
        ("visible idle bypasses hold", m.publish("working", None, visible, 1000), ("idle", None)),
        ("skip keeps state", m.publish("working", 1000, skip, 5000), ("working", 1000)),
        ("idle → idle", m.publish("idle", None, idle_plain, 1000), ("idle", None)),
    ]
    # display(): hook flags vs the published state. A stale spinner TITLE must not erase errored.
    title_rule = next(r for r in rules if r.id == "osc_title_working")
    screen_rule = next(r for r in rules if r.id == "live_turn_working")
    checks += [
        ("errored beats stale spinner title", m.display("working", title_rule, "errored", False), ("errored", False)),
        ("screen turn clears errored", m.display("working", screen_rule, "errored", False), ("working", True)),
        ("errored when idle", m.display("idle", visible, "errored", True), ("errored", False)),
        ("compacting while working", m.display("working", screen_rule, "compacting", False), ("compacting", False)),
        ("compacting spent on idle", m.display("idle", visible, "compacting", False), ("read", True)),
        ("blocked → waiting", m.display("blocked", None, "", False), ("waiting", False)),
        ("unread", m.display("idle", None, "", True), ("unread", False)),
    ]
    for name, got, want in checks:
        if got != want:
            fails += 1
            print(f"FAIL {name}: got {got}, want {want}")

    total = len(CASES) + len(checks)
    print(f"{total - fails}/{total} passed")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
