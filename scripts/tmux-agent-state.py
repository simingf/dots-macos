#!/usr/bin/env python3
"""tmux-agent-state.py — Claude Code agent state for the tmux status bar (driven by scripts/tmux-agents.sh).

State is read off the pane itself, the way herdr (github.com/herdrdev/herdr, Apache-2.0 — see
agent-detection/LICENSE) does it: the OSC title + visible screen go through herdr's Claude detection
manifest (agent-detection/claude.toml, vendored VERBATIM — refresh it with `update-rules`, never hand-edit)
via a port of herdr's rule engine (src/detect/manifest.rs) and publish logic (src/pane/agent_detection.rs).
Runs on macOS and the Linux box alike: stdlib-only Python ≥3.8 + tmux. tomllib is 3.11+, so the engine loads
claude.json — the same manifest, converted by `update-rules` (Mac); test-agent-state.py checks they match.
Hooks can't be the source of truth: turns that start without a prompt (background results, /loop wakeups)
fire no UserPromptSubmit, Esc/rejections skip Stop, and the title can sit on ✳ mid-turn.

Modes:
  status          one row per Claude pane — status<TAB>target<TAB>window<TAB>pane_id<TAB>title — busy first,
                  then most-recently-active; persists per-pane state as a side effect
  panes [win]     pane ids of the Claude panes (in one window, for tmux-rename.sh; else all)
  explain [pane]  debug one pane (or a screen on stdin, title in $TITLE): every rule's verdict + the winner
  update-rules    re-fetch claude.toml from herdr's main branch + regenerate claude.json (Mac: gh + Python ≥3.11)

Displayed status = herdr state refined by what the screen can't show:
  blocked → waiting; working → compacting while the PreCompact hook flag is set;
  idle → errored (StopFailure flag), else unread (went idle while you weren't looking), else read.

Per-pane state lives in tmux pane options, so it dies with the pane:
  @agent_state   last published herdr state (working|blocked|idle); skip_state_update rules keep it
  @agent_hold    ms timestamp of the first plain-idle read after working (herdr's pending-idle hold)
  @agent_unread  1 = went idle while not visible; cleared by `tmux-agents.sh mark-read`
Hook flags come from /tmp/agent-status-<uid>-<pane> (.claude/hooks/agent-status.sh) and are consumed here:
errored is dropped once the SCREEN shows a turn (a stale spinner title doesn't count), compacting once idle.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import json
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RULES_TOML = HERE / "agent-detection" / "claude.toml"   # herdr's file, verbatim — the reference
RULES_FILE = HERE / "agent-detection" / "claude.json"   # what the engine loads (generated from the toml)
RULES_URL = "repos/herdrdev/herdr/contents/src/detect/manifests/claude.toml"

# Which panes are Claude: herdr identifies the foreground process, but under the declawd sandbox the pane's
# process is a wrapper (pane_current_command = zsh), so the OSC title is the primary signal — spinner
# frames (braille ≤2.1.227, half-circles after), "Claude Code", or the idle ✳-family marker.
AGENT_TITLE_RE = re.compile(r"[\u2800-\u28FF\u25D0-\u25D3]|Claude Code|[✳✶✻✽]")

# herdr re-reads a held working→plain-idle transition every 100ms and publishes after 3 confirmations or a
# 700ms cap. We read on hooks / title changes / a 2s poll, so: publish once a plain-idle read lands
# ≥ HOLD_MS after the first one (any working read in between restarts it), re-checking after RECHECK_S.
HOLD_MS = 300
RECHECK_S = 0.4

FIRST = ("working", "compacting", "waiting")   # listed first in the picker (needs you / is running)
SEP = "\x1eAGENT-CAPTURE-END\x1e"


# --- herdr rule engine (src/detect/manifest.rs) ------------------------------------------------------

def _rx(pattern: str) -> re.Pattern:
    """Rust regex → Python re. Only two syntax gaps occur in the manifests: \\x{HHHH} and \\z."""
    unescaped = r"(?<!\\)((?:\\\\)*)"   # an even run of backslashes, so the \ below is a real escape
    pattern = re.sub(unescaped + r"\\x\{([0-9A-Fa-f]+)\}", lambda m: m.group(1) + "\\U%08x" % int(m.group(2), 16), pattern)
    return re.compile(re.sub(unescaped + r"\\z", r"\1\\Z", pattern))


def _lines(text: str) -> list[str]:
    """Rust str::lines(): split on \\n, drop one trailing empty piece, strip a trailing \\r."""
    parts = text.split("\n")
    if parts and parts[-1] == "":
        parts.pop()
    return [p[:-1] if p.endswith("\r") else p for p in parts]


class Gate:
    """One matcher node. All listed conditions must hold: every `contains` (case-insensitive), every
    `regex` (on the whole region), every `line_regex` (on some line), every `all` child, at least one
    `any` child (if any), and no `not` child."""

    def __init__(self, spec: dict):
        self.contains = [s.lower() for s in spec.get("contains", [])]
        self.regex = [_rx(p) for p in spec.get("regex", [])]
        self.line_regex = [_rx(p) for p in spec.get("line_regex", [])]
        self.all = [Gate(g) for g in spec.get("all", [])]
        self.any = [Gate(g) for g in spec.get("any", [])]
        self.not_ = [Gate(g) for g in spec.get("not", [])]

    def match(self, text: str, lower: str, lines: list[str]) -> bool:
        return (all(n in lower for n in self.contains)
                and all(r.search(text) for r in self.regex)
                and all(any(r.search(line) for line in lines) for r in self.line_regex)
                and all(g.match(text, lower, lines) for g in self.all)
                and (not self.any or any(g.match(text, lower, lines) for g in self.any))
                and not any(g.match(text, lower, lines) for g in self.not_))


class Rule:
    def __init__(self, spec: dict):
        self.id = spec["id"]
        self.state = spec.get("state", "unknown")
        self.priority = spec.get("priority", 0)
        self.region = spec.get("region", "whole_recent").strip()
        self.visible_idle = spec.get("visible_idle", False) and self.state == "idle"
        self.skip = spec.get("skip_state_update", False)
        self.gate = Gate(spec)

    def match(self, text: str) -> bool:
        return self.gate.match(text, text.lower(), _lines(text))


def load_rules() -> list[Rule]:
    with open(RULES_FILE, encoding="utf-8") as f:
        return [Rule(r) for r in json.load(f).get("rules", [])]


def _is_rule(line: str) -> bool:
    """A horizontal rule: starts with ─, and is either all ─ or ≥3 ─ followed by a label (Claude's
    prompt box top border carries the session name: "──── herdr ─")."""
    t = line.strip()
    n = len(t) - len(t.lstrip("─"))
    return n > 0 and (not t[n:].strip() or n >= 3)


def _prompt_box_top(lines: list[str]) -> int | None:
    """Index of the prompt box's top border = the second rule from the bottom."""
    rules = [i for i, line in enumerate(lines) if _is_rule(line)]
    return rules[-2] if len(rules) >= 2 else None


def _bottom_non_empty(lines: list[str], n: int) -> list[str]:
    idx = [i for i, line in enumerate(lines) if line.strip()][-n:]
    return lines[idx[0]:] if idx else []


def _top_non_empty(lines: list[str], n: int) -> list[str]:
    idx = [i for i, line in enumerate(lines) if line.strip()][:n]
    return lines[:idx[-1] + 1] if idx else []


def region(spec: str, screen: str, title: str, progress: str) -> str:
    """Region text a rule is matched against (herdr's region()). The Codex-only prompt-marker regions
    aren't ported; like herdr, an unknown region yields "" (so the rule can't match)."""
    if spec == "osc_title":
        return title
    if spec == "osc_progress":
        return progress
    lines = _lines(screen)
    join = "\n".join
    if spec == "whole_recent":
        return screen
    if spec == "after_last_horizontal_rule":
        last = max((i for i, line in enumerate(lines) if _is_rule(line)), default=-1)
        return join(lines[last + 1:])
    if spec in ("prompt_box_body", "above_prompt_box", "last_non_empty_above_prompt_box"):
        top = _prompt_box_top(lines)
        if spec == "prompt_box_body":
            if top is None:
                return ""
            end = next((i for i in range(top + 1, len(lines)) if _is_rule(lines[i])), len(lines))
            return join(lines[top + 1:end])
        above = lines if top is None else lines[:top]
        if spec == "above_prompt_box":
            return join(above)
        return next((line for line in reversed(above) if line.strip()), "")
    m = re.fullmatch(r"(bottom_lines|bottom_non_empty_lines|top_non_empty_lines)\(([1-9][0-9]*)\)", spec)
    if m:
        kind, n = m.group(1), int(m.group(2))
        if kind == "bottom_lines":
            return join(lines[-n:])
        return join(_bottom_non_empty(lines, n) if kind == "bottom_non_empty_lines" else _top_non_empty(lines, n))
    return ""


def detect(rules: list[Rule], screen: str, title: str, progress: str = "") -> Rule | None:
    """Highest-priority matching rule (ties → the earlier rule); None = herdr's idle fallback."""
    best = None
    for r in rules:
        if (best is None or r.priority > best.priority) and r.match(region(r.region, screen, title, progress)):
            best = r
    return best


# --- herdr publish logic (src/pane/agent_detection.rs) ----------------------------------------------

def publish(prev: str, hold: int | None, rule: Rule | None, now: int) -> tuple[str, int | None]:
    """(previous published state, hold) + this read → (state to publish, new hold).
    skip_state_update (transcript viewer, model picker) keeps everything; so does `unknown`, which herdr
    would publish as its own state but we have no dot for. A working → *plain* idle (no visible_idle rule,
    i.e. nothing positively showed the prompt) is held to ride out a frame between spinner redraws."""
    if rule is not None and (rule.skip or rule.state == "unknown"):
        return prev, hold
    state = rule.state if rule else "idle"
    if prev == "working" and state == "idle" and not (rule and rule.visible_idle):
        if hold is None or now - hold < HOLD_MS:
            return prev, hold if hold is not None else now
    return state, None


def display(state: str, rule: Rule | None, flag: str, unread: bool) -> tuple[str, bool]:
    """Published herdr state + hook flag + unread → (status shown, whether the flag is spent).
    errored outranks a working that only the TITLE shows: after an API error Claude's title often keeps its
    last spinner frame. Only screen evidence of a turn clears it; compacting is spent once idle."""
    screen_working = state == "working" and rule is not None and rule.region != "osc_title"
    if flag == "errored" and not screen_working:
        return "errored", False
    if state == "blocked":
        return "waiting", False
    if state == "working":
        return ("compacting" if flag == "compacting" else "working"), flag == "errored"
    return ("unread" if unread else "read"), flag == "compacting"


# --- tmux glue -------------------------------------------------------------------------------------

PANE_FIELDS = ["pane_id", "session_name", "window_index", "pane_index", "window_name", "window_activity",
               "pane_current_command", "visible", "@agent_state", "@agent_hold", "@agent_unread",
               "pane_title"]   # free text last: split("\t", n-1) keeps a tab inside it
PANE_FORMAT = "\t".join("#{%s}" % f if f != "visible" else
                        "#{&&:#{session_attached},#{&&:#{window_active},#{pane_active}}}" for f in PANE_FIELDS)


def tmux(*args: str) -> str:
    # tmux emits UTF-8 whatever the locale; decode it as such (a C-locale run-shell would otherwise mangle ❯/✻).
    return subprocess.run(["tmux", *args], capture_output=True, encoding="utf-8", errors="replace").stdout


def claude_panes(*target: str) -> list[dict]:
    out = tmux("list-panes", *(target or ("-a",)), "-F", PANE_FORMAT)
    panes = [dict(zip(PANE_FIELDS, line.split("\t", len(PANE_FIELDS) - 1))) for line in out.splitlines()]
    return [p for p in panes if len(p) == len(PANE_FIELDS)
            and (p["pane_current_command"] == "claude" or AGENT_TITLE_RE.search(p["pane_title"]))]


def capture(pane_ids: list[str]) -> list[str]:
    """Visible screen of each pane — one tmux call, separated by a marker line. If a pane vanished
    mid-call tmux aborts the rest of the sequence, so fall back to one call per pane."""
    if not pane_ids:
        return []
    args: list[str] = []
    for pid in pane_ids:
        args += ["capture-pane", "-p", "-t", pid, ";", "display-message", "-p", SEP, ";"]
    parts = tmux(*args[:-1]).split(SEP + "\n")
    if len(parts) == len(pane_ids) + 1:
        return parts[:-1]
    return [tmux("capture-pane", "-p", "-t", pid) for pid in pane_ids]


def _flagf(pane_id: str) -> Path:
    return Path(f"/tmp/agent-status-{os.getuid()}-{pane_id.lstrip('%')}")


def status() -> None:
    rules = load_rules()
    panes = claude_panes()
    now = int(time.time() * 1000)
    sets: list[str] = []   # batched tmux commands, ";"-separated
    held = False
    rows = []
    for p, screen in zip(panes, capture([p["pane_id"] for p in panes])):
        pid, prev = p["pane_id"], p["@agent_state"]
        old_hold = int(p["@agent_hold"]) if p["@agent_hold"].isdigit() else None
        old_unread = unread = p["@agent_unread"] == "1"
        rule = detect(rules, screen, p["pane_title"])
        state, hold = publish(prev, old_hold, rule, now)
        if state != prev and state != "idle":
            unread = False                                       # a new turn: the old "done" is moot
        elif state == "idle" and prev in ("working", "blocked") and p["visible"] != "1":
            unread = True                                        # finished while you weren't looking

        if state != prev:
            sets += ["set-option", "-p", "-t", pid, "@agent_state", state, ";"]
        if hold != old_hold:
            sets += (["set-option", "-p", "-t", pid, "@agent_hold", str(hold), ";"] if hold is not None
                     else ["set-option", "-pu", "-t", pid, "@agent_hold", ";"])
        if unread != old_unread:
            sets += (["set-option", "-p", "-t", pid, "@agent_unread", "1", ";"] if unread
                     else ["set-option", "-pu", "-t", pid, "@agent_unread", ";"])
        held |= hold is not None

        flagf = _flagf(pid)
        st, drop_flag = display(state, rule, flagf.read_text().strip() if flagf.exists() else "", unread)
        if drop_flag:
            flagf.unlink(missing_ok=True)
        target = f"{p['session_name']}:{p['window_index']}.{p['pane_index']}"
        rows.append((st in FIRST, int(p["window_activity"] or 0), st, target, p["window_name"], pid, p["pane_title"]))

    if sets:
        tmux(*sets[:-1])
    if held:   # re-read once the hold can expire, rather than waiting for the next poll
        tmux("run-shell", "-b", "-d", str(RECHECK_S), f"'{HERE / 'tmux-agents.sh'}' refresh")
    for row in sorted(rows, key=lambda r: (not r[0], -r[1])):
        print("\t".join(row[2:]))


def explain(target: str | None) -> None:
    rules = load_rules()
    if target:
        screen = capture([target])[0]
        title = tmux("display-message", "-p", "-t", target, "#{pane_title}").rstrip("\n")
    else:
        screen, title = sys.stdin.read(), os.environ.get("TITLE", "")
    win = detect(rules, screen, title)
    print(f"title: {title!r}")
    for r in rules:   # * = winner, + = matched but outranked; matched rules show the tail of their region
        text = region(r.region, screen, title, "")
        hit = r.match(text)
        line = f"{'*' if r is win else '+' if hit else ' '} {r.priority:>4} {r.state:<8} {r.id}"
        print(f"{line:<52} {r.region}: {text[-80:]!r}" if hit else line)
    print("=>", f"{win.state} ({win.id})" if win else "idle (no rule matched → fallback)")


def toml_to_json(body: str) -> str:
    import tomllib   # 3.11+, only needed here (Mac)
    return json.dumps(tomllib.loads(body), ensure_ascii=False, indent=1) + "\n"


def update_rules() -> None:
    body = subprocess.run(["gh", "api", RULES_URL, "-H", "Accept: application/vnd.github.raw"],
                          capture_output=True, encoding="utf-8", check=True).stdout
    generated = toml_to_json(body)
    manifest = json.loads(generated)
    [Rule(r) for r in manifest.get("rules", [])]   # every regex must compile in Python — else write nothing
    RULES_TOML.write_text(body, encoding="utf-8")
    RULES_FILE.write_text(generated, encoding="utf-8")
    print(manifest["version"])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")   # titles/screens are UTF-8 even under a C locale
    sys.stdin.reconfigure(encoding="utf-8")
    mode, args = (sys.argv[1] if len(sys.argv) > 1 else "status"), sys.argv[2:]
    if mode == "status":
        status()
    elif mode == "panes":
        for p in claude_panes(*(("-t", args[0]) if args else ())):
            print(p["pane_id"])
    elif mode == "explain":
        explain(args[0] if args else None)
    elif mode == "update-rules":
        update_rules()
    else:
        sys.exit(f"tmux-agent-state: unknown mode {mode!r} (status|panes|explain|update-rules)")
