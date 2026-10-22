#!/usr/bin/env python3
"""agent-clip.py — Stop hook: copy every user-facing block of this turn's reply to the clipboard.

User-facing = in the turn's reply text, top to bottom:
  - fenced blocks, any language (commands, drafts, snippets; one clip per block, list indent removed,
    `$ ` prompts stripped from shell blocks)
  - `>` blockquotes (drafts / quoted wording; one clip per quote, `> ` removed)
  - `! cmd` lines / inline code spans (the "type `! cmd` in the prompt" form, copied verbatim)
Skipped: anything the agent ran itself (equal to a Bash tool call's command this turn).

Each block is a separate `pbcopy` with a CLIP_GAP pause so clipboard history (Alfred) records
them all, last block = current clipboard. pbcopy on the Linux box forwards to the Mac via OSC 52.
Runs detached (the hook returns immediately); never fails the hook.
"""
import json
import os
import re
import subprocess
import sys
import time

CLIP_GAP = 1.0  # seconds between copies; clipboard managers poll, faster copies get dropped
SHELL_LANGS = {"bash", "sh", "zsh", "shell", "console"}
FENCE = re.compile(r"^([ \t]*)```([\w-]*)[^\n]*\n(.*?)^\1```", re.M | re.S)
QUOTE = re.compile(r"(?:^[ \t]*>.*(?:\n|$))+", re.M)
QUOTE_MARK = re.compile(r"^[ \t]*> ?", re.M)
BANG = re.compile(r"(?:^|`)(! [^`\n]+)", re.M)


def is_prompt(r):
    """A real user prompt: not a tool_result / meta message. Messages sent mid-turn are
    `queued_command` attachments, not user rows, so they never split a turn."""
    if r.get("type") != "user" or r.get("isMeta") or r.get("isSidechain"):
        return False
    c = (r.get("message") or {}).get("content")
    return isinstance(c, str) or any(b.get("type") == "text" for b in c or [])


def last_prompt(rows):
    return next((r.get("uuid") for r in reversed(rows) if is_prompt(r)), None)


def turn_entries(rows, anchor=None):
    """Entries after prompt `anchor` (default: the last prompt), up to the next prompt."""
    anchor = anchor or last_prompt(rows)
    start = next((i + 1 for i, r in enumerate(rows) if anchor and r.get("uuid") == anchor), 0)
    end = next((i for i in range(start, len(rows)) if is_prompt(rows[i])), len(rows))
    return rows[start:end]


def read(tp):
    with open(tp) as f:
        return [json.loads(l) for l in f if l.strip()]


def norm(s):
    return " ".join(s.split())


def clips(rows, anchor=None):
    texts, ran = [], []
    for r in turn_entries(rows, anchor):
        if r.get("type") != "assistant" or r.get("isSidechain"):
            continue
        for b in (r.get("message") or {}).get("content") or []:
            if b.get("type") == "text":
                texts.append(b.get("text", ""))
            elif b.get("type") == "tool_use" and b.get("name") == "Bash":
                ran.append(b.get("input", {}).get("command", ""))

    found = []  # (offset in joined text, clip) so fences, quotes and `!` lines interleave in order
    text = "\n".join(texts)
    fenced = []
    for m in FENCE.finditer(text):
        fenced.append(m.span())
        indent, shell = len(m.group(1)), m.group(2).lower() in SHELL_LANGS
        lines = [l[indent:] for l in m.group(3).rstrip("\n").split("\n")]
        if shell:
            lines = [l[2:] if l.startswith("$ ") else l for l in lines]
        found.append((m.start(), "\n".join(lines)))
    in_fence = lambda i: any(a <= i < b for a, b in fenced)  # quotes / `!` lines inside fences belong to the fence
    for m in QUOTE.finditer(text):
        if not in_fence(m.start()):
            found.append((m.start(), QUOTE_MARK.sub("", m.group(0)).strip("\n")))
    for m in BANG.finditer(text):
        if not in_fence(m.start()) and not text[:m.start()].rsplit("\n", 1)[-1].lstrip().startswith(">"):
            found.append((m.start(1), m.group(1).strip()))

    ran_n = {norm(c) for c in ran}
    out = []
    for _, cmd in sorted(found):
        n = norm(cmd)
        if not n or n in ran_n or cmd in out:
            continue
        out.append(cmd)
    return out


def main():
    try:
        tp = json.load(sys.stdin).get("transcript_path") or ""
    except Exception:
        return
    if not tp:
        return
    # Pin the turn's prompt now: a queued message can start the next turn during the sleep below.
    anchor = last_prompt(read(tp))
    if os.fork():  # parent returns at once; child does the work
        return
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    time.sleep(0.5)  # let the final message land in the transcript
    cmds = clips(read(tp), anchor)
    for i, cmd in enumerate(cmds):
        if i:
            time.sleep(CLIP_GAP)
        subprocess.run(["pbcopy"], input=cmd.encode())
    if cmds and os.environ.get("TMUX_PANE"):
        dots = subprocess.run(["tmux", "show-environment", "-g", "DOTFILES_DIR"],
                              capture_output=True, text=True).stdout.strip().partition("=")[2]
        notify = os.path.join(dots, "scripts/tmux-notify.sh")
        if os.access(notify, os.X_OK):
            msg = f"copied: {cmds[0][:40]}" if len(cmds) == 1 else f"copied {len(cmds)} blocks"
            subprocess.run([notify, msg], env={**os.environ, "NOTIFY_TARGET": os.environ["TMUX_PANE"]})


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
