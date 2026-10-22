#!/usr/bin/env python3
"""End-to-end regression test for the ⌘-key / selection keybinds (KEYBINDS.md "⌘ shortcuts").

Drives the real path minus the keyboard: the bytes ghostty would send (read from
`ghostty +list-keybinds`, so the ghostty layer is checked too) are typed into a real tmux client
attached to a throwaway server running ~/.tmux.conf, whose User binds call scripts/tmux-cmdkey.sh,
which drives real zsh / nvim panes and a fake Claude Code pane (records the bytes it receives).

Isolation: everything runs on private tmux sockets (-L kbtest / -L kbouter) — tmux-cmdkey.sh's own
`tmux` calls inherit the test server's $TMUX, so the live tmux server is never touched. nvim gets a
fake clipboard (no pbcopy) and zsh's OSC 52 copies land in the test server's paste buffer.

usage: scripts/test-keybinds.py [-k <substring>]   # -k: only run cases whose name contains it
"""
import argparse
import codecs
import json
import os
import shutil
import subprocess
import sys
import time

TMP = "/tmp/kbtest"
INNER, OUTER = "kbtest", "kbouter"
DOTS = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
TMUX_CONF = os.path.join(DOTS, ".tmux.conf")


# ── plumbing ────────────────────────────────────────────────────────────────────────────────────
def tmux(*args, sock=INNER, check=False):
    r = subprocess.run(["tmux", "-L", sock, *args], capture_output=True, text=True)
    if check and r.returncode:
        raise RuntimeError(f"tmux {args}: {r.stderr}")
    return r.stdout.rstrip("\n")


def ghostty_text_binds():
    """ghostty trigger → bytes, for every `text:` keybind ghostty actually resolved."""
    out = subprocess.run(["ghostty", "+list-keybinds"], capture_output=True, text=True).stdout
    binds = {}
    for line in out.splitlines():
        line = line.removeprefix("keybind = ")
        trigger, _, action = line.partition("=")
        if action.startswith("text:"):
            raw = action[5:].replace("\\\\", "\\")
            binds[trigger] = codecs.decode(raw, "unicode_escape").encode("latin-1")
    return binds


GHOSTTY = {  # test key name → ghostty trigger
    "cmd+a": "super+a", "cmd+c": "super+c", "cmd+x": "super+x", "cmd+z": "super+z",
    "cmd+shift+z": "super+shift+z", "cmd+left": "super+arrow_left", "cmd+right": "super+arrow_right",
    "cmd+s": "super+s", "cmd+shift+bs": "super+shift+backspace", "cmd+f": "super+f", "cmd+p": "super+p",
    "cmd+slash": "super+slash", "cmd+]": "super+bracket_right", "cmd+[": "super+bracket_left",
    "cmd+bs": "super+backspace", "cmd+shift+left": "super+shift+arrow_left",
    "cmd+shift+right": "super+shift+arrow_right", "alt+bs": "alt+backspace",
}
RAW = {  # keys ghostty sends natively (no keybind)
    "S-left": b"\x1b[1;2D", "S-right": b"\x1b[1;2C", "left": b"\x1b[D", "right": b"\x1b[C",
    "bs": b"\x7f", "esc": b"\x1b", "enter": b"\r",
}
KEYS = {}


def press(key):
    if key.startswith("type:"):
        data = key[5:].encode()
    elif key.startswith("paste:"):
        data = b"\x1b[200~" + key[6:].encode() + b"\x1b[201~"
    else:
        data = KEYS[key]
    tmux("send-keys", "-t", "O", "-H", *[f"{b:02x}" for b in data], sock=OUTER)
    # ⌘ keys go through run-shell → tmux-cmdkey.sh → tmux send-keys: give that chain time to land
    time.sleep(0.35 if key in GHOSTTY else 0.12)


def wait_for(fn, timeout=8.0):
    end = time.time() + timeout
    while time.time() < end:
        if fn():
            return True
        time.sleep(0.1)
    return False


def clip_reset():
    while tmux("list-buffers"):
        tmux("delete-buffer")


def clip():
    return tmux("show-buffer") if tmux("list-buffers") else None


def prompt_closed_by_esc():
    """Esc must close a tmux command prompt (⌘F search); C-c fallback so a failure can't leak."""
    press("esc")
    time.sleep(0.2)
    if "search up" not in tmux("capture-pane", "-p", "-t", "O", sock=OUTER):
        return []
    tmux("send-keys", "-t", "O", "C-c", sock=OUTER)
    time.sleep(0.2)
    return ["Esc didn't close the search prompt"]


def select(win):
    tmux("select-window", "-t", f"T:{win}")
    time.sleep(0.15)


# ── zsh ─────────────────────────────────────────────────────────────────────────────────────────
def zq(s):  # zsh $'…' quoting
    return "$'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'"


def parse_caret(s):
    i = s.index("|")
    return s[:i] + s[i + 1:], i


def zsh_state():
    try:
        os.remove(f"{TMP}/zsh.state")
    except FileNotFoundError:
        pass
    tmux("send-keys", "-t", "T:zsh", "C-x", "d")
    wait_for(lambda: os.path.exists(f"{TMP}/zsh.state"), 3)
    time.sleep(0.05)
    with open(f"{TMP}/zsh.state") as f:
        cur, _, buf = f.read().partition("\n")
    return buf, int(cur)


def zsh_case(name, start, keys, want, want_clip=None, extra=None):
    buf, cur = parse_caret(start)
    with open(f"{TMP}/zsh.init", "w") as f:
        f.write(f"BUFFER={zq(buf)}; CURSOR={cur}; MARK=0; REGION_ACTIVE=0\n")
    clip_reset()
    tmux("send-keys", "-t", "T:zsh", "C-x", "r")
    time.sleep(0.15)
    for k in keys:
        press(k)
    problems = []
    if extra:
        problems += extra()
    got_buf, got_cur = zsh_state()
    got = got_buf[:got_cur] + "|" + got_buf[got_cur:]
    if want is not None and got != want:
        problems.append(f"buffer {got!r}, want {want!r}")
    if want_clip is not None and clip() != want_clip:
        problems.append(f"clipboard {clip()!r}, want {want_clip!r}")
    return problems


# ── nvim ────────────────────────────────────────────────────────────────────────────────────────
NV_SOCK = f"{TMP}/nvim.sock"
NV_FILE = f"{TMP}/t.lua"
FAKE_CLIP = (
    "lua local function c(l) vim.g.kb_clip = table.concat(l, '\\n') end "
    "local function p() return { vim.split(vim.g.kb_clip or '', '\\n'), 'v' } end "
    "vim.g.clipboard = { name = 'kbtest', copy = { ['+'] = c, ['*'] = c }, paste = { ['+'] = p, ['*'] = p } }"
)
NV_STATE = """luaeval('(function()
  local c = vim.api.nvim_win_get_cursor(0)
  local v = vim.fn.getpos("v")
  local floats = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "wk" then floats = floats + 1 end
  end
  return vim.json.encode({ lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), row = c[1], col = c[2],
    mode = vim.api.nvim_get_mode().mode, vrow = v[2], vcol = v[3] - 1, clip = vim.g.kb_clip or vim.NIL,
    modified = vim.bo.modified, ft = vim.bo.filetype, cmdtype = vim.fn.getcmdtype(), floats = floats })
end)()')"""
NV_BASE_FLOATS = 0


def nv_expr(e):
    return subprocess.run(["nvim", "--server", NV_SOCK, "--remote-expr", e], capture_output=True, text=True).stdout


def nv_send(keys):
    subprocess.run(["nvim", "--server", NV_SOCK, "--remote-send", keys], capture_output=True)
    time.sleep(0.12)


def nv_lua(code):
    return nv_expr(f"luaeval('{code}')")


def nv_state():
    return json.loads(nv_expr(NV_STATE))


L = "    foo bar baz"  # cols: f=4 b=8 r=10 b=12 z=14 (last)


def nv_case(name, lines, pos, mode, keys, want_lines=None, want_mode=None, want_cur=None, want_sel=None,
            want_clip=None, check=None, cleanup=None):
    """pos = (row, col) 1-based row / 0-based col. mode: n | i | i$ (caret at EOL) | v:<endcol>."""
    nv_send("<C-\\><C-N><Esc>")
    js = json.dumps(lines).replace("'", "\\'")
    nv_lua(f'(function() vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.json.decode([=[{js}]=])) '
           f'vim.api.nvim_win_set_cursor(0, {{{pos[0]}, {pos[1]}}}) vim.g.kb_clip = nil return 1 end)()')
    if mode == "i":
        nv_send("<Cmd>startinsert<CR>")
    elif mode == "i$":
        nv_send("<Cmd>startinsert!<CR>")
    elif mode.startswith("v:"):
        nv_send("v<Ignore>")
        nv_lua(f"vim.api.nvim_win_set_cursor(0, {{{pos[0]}, {mode[2:]}}})")
    time.sleep(0.1)
    for k in keys:
        press(k)
    time.sleep(0.1)
    s = nv_state()
    problems = []
    if want_lines is not None and s["lines"] != want_lines:
        problems.append(f"lines {s['lines']!r}, want {want_lines!r}")
    if want_mode is not None and s["mode"] != want_mode:
        problems.append(f"mode {s['mode']!r}, want {want_mode!r}")
    if want_cur is not None and s["col"] != want_cur:
        problems.append(f"cursor col {s['col']}, want {want_cur}")
    if want_sel is not None:
        sel = (min(s["vcol"], s["col"]), max(s["vcol"], s["col"])) if s["mode"] in ("v", "V") else None
        if sel != want_sel:
            problems.append(f"selection {sel} (mode {s['mode']}), want cols {want_sel}")
    if want_clip is not None and s["clip"] != want_clip:
        problems.append(f"clipboard {s['clip']!r}, want {want_clip!r}")
    if check:
        problems += check(s)
    if not cleanup and s["floats"] > NV_BASE_FLOATS:
        problems.append("which-key popup opened")
    if cleanup:
        cleanup()
    return problems


# ── fake Claude Code / other app ────────────────────────────────────────────────────────────────
REC = """import os, sys, tty
sys.stdout.write("\\x1b]2;" + sys.argv[1] + "\\x07"); sys.stdout.flush()
tty.setraw(0)
with open(sys.argv[2], "ab", 0) as f:
    while True:
        b = os.read(0, 1024)
        if not b: break
        f.write(b)
"""


def rec_case(win, keys, want, extra=None):
    path = f"{TMP}/{win}.rec"
    open(path, "wb").close()
    tmux("set", "-gu", "@notify")
    for k in keys:
        press(k)
    time.sleep(0.2)
    got = open(path, "rb").read()
    problems = []
    ok = got in want if isinstance(want, tuple) else got == want
    if not ok:
        problems.append(f"pane received {got!r}, want {want!r}")
    if extra:
        problems += extra()
    return problems


# ── setup ───────────────────────────────────────────────────────────────────────────────────────
def setup():
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    for s in (INNER, OUTER):
        tmux("kill-server", sock=s)
    env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")}
    env["HISTFILE"] = f"{TMP}/zsh_history"
    subprocess.run(["tmux", "-L", INNER, "-f", TMUX_CONF, "new-session", "-d", "-s", "T", "-n", "zsh",
                    "-x", "200", "-y", "50", "zsh -i"], env=env, check=True)
    with open(f"{TMP}/rec.py", "w") as f:
        f.write(REC)
    with open(NV_FILE, "w") as f:
        f.write(L + "\n")
    tmux("new-window", "-d", "-t", "T:", "-n", "nvim", f"nvim -n --listen {NV_SOCK} --cmd \"{FAKE_CLIP}\" {NV_FILE}")
    tmux("new-window", "-d", "-t", "T:", "-n", "claude", f"python3 {TMP}/rec.py '✳ Claude Code' {TMP}/claude.rec")
    tmux("new-window", "-d", "-t", "T:", "-n", "busy", f"python3 {TMP}/rec.py '⠂ Working on it' {TMP}/busy.rec")
    tmux("new-window", "-d", "-t", "T:", "-n", "other", f"python3 {TMP}/rec.py 'plain app' {TMP}/other.rec")
    tmux("new-window", "-d", "-t", "T:", "-n", "copy", "printf 'alpha beta\\n'; exec sleep 100000")
    subprocess.run(["tmux", "-L", OUTER, "-f", "/dev/null", "new-session", "-d", "-s", "O", "-x", "200",
                    "-y", "50", f"env -u TMUX -u TMUX_PANE tmux -L {INNER} attach -t T:zsh"], env=env, check=True)
    if not wait_for(lambda: tmux("list-clients"), 5):
        sys.exit("test tmux client never attached")
    wait_for(lambda: tmux("display", "-p", "-t", "T:zsh", "#{pane_current_command}") == "zsh")
    time.sleep(2.5)  # zsh -i: plugins + prompt
    tmux("send-keys", "-t", "T:zsh", "-l",
         " ZSH_AUTOSUGGEST_STRATEGY=(); "
         f"_kbinit() {{ source {TMP}/zsh.init }}; "
         f"_kbdump() {{ print -r -- $CURSOR >| {TMP}/zsh.state; print -rn -- \"$BUFFER\" >> {TMP}/zsh.state }}; "
         "zle -N _kbinit; zle -N _kbdump; bindkey '^Xr' _kbinit; bindkey '^Xd' _kbdump")
    tmux("send-keys", "-t", "T:zsh", "Enter")
    time.sleep(1.5)
    press("cmd+s")  # warm-up: the first keys after attach can race tmux's own terminal queries
    time.sleep(0.5)
    wait_for(lambda: os.path.exists(NV_SOCK) and nv_expr("1") == "1")
    time.sleep(2)  # lazy.nvim VeryLazy plugins (which-key)
    global NV_BASE_FLOATS
    NV_BASE_FLOATS = nv_state()["floats"]


# ── cases ───────────────────────────────────────────────────────────────────────────────────────
def zsh_cases():
    def in_copy_mode():
        st = tmux("display", "-p", "-t", "T:zsh", "#{pane_in_mode} #{pane_current_command}")
        problems = prompt_closed_by_esc()
        tmux("send-keys", "-t", "T:zsh", "-X", "cancel")
        return problems + ([] if st.startswith("1") else [f"not in tmux copy-mode ({st})"])

    c = zsh_case
    return [
        ("zsh ⌘← mid → first non-blank", lambda: c(0, "  echo hel|lo", ["cmd+left"], "  |echo hello")),
        ("zsh ⌘← from col 0 → first non-blank", lambda: c(0, "|  echo", ["cmd+left"], "  |echo")),
        ("zsh ⌘→ → end", lambda: c(0, "  ec|ho", ["cmd+right"], "  echo|")),
        ("zsh ⌘← multi-line: current line only", lambda: c(0, "a\n  bc|d", ["cmd+left"], "a\n  |bcd")),
        ("zsh ⇧←⇧← then type replaces", lambda: c(0, "abc|d", ["S-left", "S-left", "type:X"], "aX|d")),
        ("zsh ⇧→⇧→ then type replaces", lambda: c(0, "a|bcd", ["S-right", "S-right", "type:X"], "aX|d")),
        ("zsh ⇧← at col 0 then type", lambda: c(0, "|abc", ["S-left", "type:X"], "X|abc")),
        ("zsh ⇧→ at end then type", lambda: c(0, "abc|", ["S-right", "type:X"], "abcX|")),
        ("zsh ⇧⌘← then type", lambda: c(0, "  echo hel|lo", ["cmd+shift+left", "type:X"], "  X|lo")),
        ("zsh ⇧⌘→ then type", lambda: c(0, "echo hel|lo", ["cmd+shift+right", "type:X"], "echo helX|")),
        ("zsh ⇧⌘← then ⌫", lambda: c(0, "  echo hel|lo", ["cmd+shift+left", "bs"], "  |lo")),
        ("zsh ⇧⌘→ then ⌫", lambda: c(0, "echo hel|lo", ["cmd+shift+right", "bs"], "echo hel|")),
        ("zsh ⇧← then ⇧⌘← extends", lambda: c(0, "ab cd|", ["S-left", "cmd+shift+left", "type:X"], "X|")),
        ("zsh ⌘A then type", lambda: c(0, "foo |bar", ["cmd+a", "type:X"], "X|")),
        ("zsh ⌘A then ⌫", lambda: c(0, "foo |bar", ["cmd+a", "bs"], "|")),
        ("zsh ⌘A ⌘C copies", lambda: c(0, "foo |bar", ["cmd+a", "cmd+c"], "foo bar|", "foo bar")),
        ("zsh ⇧⌘← ⌘X cuts", lambda: c(0, "foo ba|r", ["cmd+shift+left", "cmd+x"], "|r", "foo ba")),
        ("zsh ⌘C with no selection is a no-op", lambda: c(0, "foo|", ["cmd+c"], "foo|")),
        ("zsh plain arrow drops the selection", lambda: c(0, "abc|d", ["S-left", "left", "type:X"], "aX|bcd")),
        ("zsh paste replaces selection", lambda: c(0, "abc|d", ["S-left", "S-left", "paste:XY"], "aXY|d")),
        ("zsh ⌫ deletes a char", lambda: c(0, "abc|", ["bs"], "ab|")),
        ("zsh ⌥⌫ deletes a word", lambda: c(0, "echo hello wor|", ["alt+bs"], "echo hello |")),
        ("zsh ⌥⌫ deletes the selection", lambda: c(0, "echo hello|", ["S-left", "S-left", "alt+bs"], "echo hel|")),
        ("zsh ⌘⌫ mid → to first non-blank", lambda: c(0, "  echo hel|lo", ["cmd+bs"], "  |lo")),
        ("zsh ⌘⌫ at end", lambda: c(0, "  echo hello|", ["cmd+bs"], "  |")),
        ("zsh ⌘⌫ at first non-blank → indent", lambda: c(0, "  |echo", ["cmd+bs"], "|echo")),
        ("zsh ⌘⌫ at col 0 is a no-op", lambda: c(0, "|echo", ["cmd+bs"], "|echo")),
        ("zsh ⌘⌫ twice clears the indent too", lambda: c(0, "  echo hi|", ["cmd+bs", "cmd+bs"], "|")),
        ("zsh ⌘⌫ deletes the selection", lambda: c(0, "abcd|", ["S-left", "S-left", "cmd+bs"], "ab|")),
        ("zsh ⌘⌫ multi-line: current line only", lambda: c(0, "a\nbc|d", ["cmd+bs"], "a\n|d")),
        ("zsh ⇧⌘⌫ clears the whole command", lambda: c(0, "a\nb|c", ["cmd+shift+bs"], "|")),
        ("zsh ⌘Z ⇧⌘Z undo/redo round-trip", lambda: c(0, "|", ["type:abc", "cmd+z", "cmd+shift+z"], "abc|")),
        ("zsh ⌘Z undoes typing", lambda: c(0, "x|", ["type: abc", "cmd+z", "cmd+z", "cmd+z", "cmd+z"], "x|")),
        ("zsh ⌘S ⌘P ⌘/ ⌘] ⌘[ are no-ops",
         lambda: c(0, "ab|c", ["cmd+s", "cmd+p", "cmd+slash", "cmd+]", "cmd+["], "ab|c")),
        ("zsh ⌘F → tmux copy-mode search", lambda: c(0, "ab|", ["cmd+f"], None, extra=in_copy_mode)),
    ]


def nvim_cases():
    c = nv_case

    def esc_out():
        nv_send("<C-\\><C-N><Esc>")
        press("esc")
        press("esc")
        time.sleep(0.3)

    def cmdline_slash(s):
        return [] if s["cmdtype"] == "/" else [f"not in / cmdline (mode {s['mode']})"]

    def picker(s):
        return [] if s["ft"].startswith("snacks_picker") else [f"no snacks picker (ft {s['ft']!r})"]

    def written(s):
        disk = open(NV_FILE).read().splitlines()
        return [] if disk == s["lines"] and not s["modified"] else [f"not written: disk {disk!r}"]

    two = [L, "next"]
    return [
        # normal mode
        ("nvim n ⌘← → first non-blank", lambda: c("", two, (1, 10), "n", ["cmd+left"], want_cur=4)),
        ("nvim n ⌘→ → last char", lambda: c("", two, (1, 4), "n", ["cmd+right"], want_cur=14)),
        ("nvim n ⇧→ selects start + next", lambda: c("", two, (1, 8), "n", ["S-right"], want_sel=(8, 9))),
        ("nvim n ⇧→⇧→ extends", lambda: c("", two, (1, 8), "n", ["S-right", "S-right"], want_sel=(8, 10))),
        ("nvim n ⇧← selects start + prev", lambda: c("", two, (1, 8), "n", ["S-left"], want_sel=(7, 8))),
        ("nvim n ⇧← at col 0", lambda: c("", ["abc"], (1, 0), "n", ["S-left"], want_sel=(0, 0))),
        ("nvim n ⇧→ at last char", lambda: c("", two, (1, 14), "n", ["S-right"], want_sel=(14, 14))),
        ("nvim n ⇧⌘← selects to first non-blank", lambda: c("", two, (1, 8), "n", ["cmd+shift+left"], want_sel=(4, 8))),
        ("nvim n ⇧⌘→ selects to line end", lambda: c("", two, (1, 8), "n", ["cmd+shift+right"], want_sel=(8, 14))),
        ("nvim n ⇧→ then ⇧⌘→", lambda: c("", two, (1, 8), "n", ["S-right", "cmd+shift+right"], want_sel=(8, 14))),
        ("nvim n ⌘⌫ mid = ⇧⌘← + ⌫", lambda: c("", two, (1, 8), "n", ["cmd+bs"], ["    ar baz", "next"], "n", 4)),
        ("nvim n ⌘⌫ on last char clears to indent",
         lambda: c("", two, (1, 14), "n", ["cmd+bs"], ["    ", "next"], "n")),
        ("nvim n ⌘⌫ at first non-blank → indent",
         lambda: c("", two, (1, 4), "n", ["cmd+bs"], ["foo bar baz", "next"], "n", 0)),
        ("nvim n ⌘⌫ twice clears the indent too",
         lambda: c("", two, (1, 8), "n", ["cmd+bs", "cmd+bs"], ["ar baz", "next"], "n", 0)),
        ("nvim n ⌘⌫ at col 0 is a no-op", lambda: c("", ["abc"], (1, 0), "n", ["cmd+bs"], ["abc"], "n")),
        ("nvim n ⇧⌘⌫ clears the line", lambda: c("", two, (1, 8), "n", ["cmd+shift+bs"], ["    ", "next"], "i")),
        ("nvim n ⌘A selects all", lambda: c("", two, (1, 8), "n", ["cmd+a"], want_mode="V",
                                             check=lambda s: [] if (s["vrow"], s["row"]) == (1, 2) else [f"rows {s['vrow']}-{s['row']}"])),
        ("nvim n ⌘Z ⇧⌘Z undo/redo", lambda: c("", two, (1, 8), "n", ["cmd+bs", "cmd+z"], two, "n")),
        ("nvim n ⇧⌘Z redoes", lambda: c("", two, (1, 8), "n", ["cmd+bs", "cmd+z", "cmd+shift+z"], ["    ar baz", "next"])),
        ("nvim n ⌘S writes", lambda: c("", ["    written n"], (1, 4), "n", ["cmd+s"], check=written)),
        ("nvim n ⌘/ toggles comment", lambda: c("", two, (1, 8), "n", ["cmd+slash"], ["    -- foo bar baz", "next"], "n")),
        ("nvim n ⌘] ⌘[ indent/outdent", lambda: c("", two, (1, 8), "n", ["cmd+]", "cmd+["], two, "n")),
        ("nvim n ⌘] indents", lambda: c("", ["foo"], (1, 0), "n", ["cmd+]"],
                                         check=lambda s: [] if s["lines"][0].strip() == "foo" and s["lines"][0] != "foo" else [f"{s['lines']!r}"])),
        ("nvim n ⌘C ⌘X are no-ops", lambda: c("", two, (1, 8), "n", ["cmd+c", "cmd+x"], two, "n")),
        ("nvim n ⌘F → / search", lambda: c("", two, (1, 8), "n", ["cmd+f"], check=cmdline_slash, cleanup=esc_out)),
        ("nvim n ⌘P → file picker", lambda: c("", two, (1, 8), "n", ["cmd+p"], check=picker, cleanup=esc_out)),
        # insert mode (pos col = caret before that char)
        ("nvim i ⌘← → first non-blank", lambda: c("", two, (1, 10), "i", ["cmd+left"], two, "i", 4)),
        ("nvim i ⌘→ → EOL", lambda: c("", two, (1, 4), "i", ["cmd+right"], two, "i", 15)),
        ("nvim i ⇧→ selects next char", lambda: c("", two, (1, 8), "i", ["S-right"], want_sel=(8, 8))),
        ("nvim i ⇧← selects prev char", lambda: c("", two, (1, 8), "i", ["S-left"], want_sel=(7, 7))),
        ("nvim i ⇧← at col 0 is a no-op", lambda: c("", ["abc"], (1, 0), "i", ["S-left"], ["abc"], "i", 0)),
        ("nvim i ⇧→ at EOL is a no-op", lambda: c("", two, (1, 0), "i$", ["S-right"], two, "i", 15)),
        ("nvim i ⇧⌘← selects to first non-blank", lambda: c("", two, (1, 8), "i", ["cmd+shift+left"], want_sel=(4, 7))),
        ("nvim i ⇧⌘→ selects to line end", lambda: c("", two, (1, 8), "i", ["cmd+shift+right"], want_sel=(8, 14))),
        ("nvim i ⇧⌘→ at EOL is a no-op", lambda: c("", two, (1, 0), "i$", ["cmd+shift+right"], two, "i", 15)),
        ("nvim i ⇧⌘← at col 0 is a no-op", lambda: c("", ["abc"], (1, 0), "i", ["cmd+shift+left"], ["abc"], "i", 0)),
        ("nvim i ⌘⌫ mid → to first non-blank", lambda: c("", two, (1, 8), "i", ["cmd+bs"], ["    bar baz", "next"], "i", 4)),
        ("nvim i ⌘⌫ at EOL", lambda: c("", two, (1, 0), "i$", ["cmd+bs"], ["    ", "next"], "i", 4)),
        ("nvim i ⌘⌫ at first non-blank → indent", lambda: c("", two, (1, 4), "i", ["cmd+bs"], ["foo bar baz", "next"], "i", 0)),
        ("nvim i ⌘⌫ after typing deletes past the typed text",
         lambda: c("", two, (1, 0), "i$", ["type: qux", "cmd+bs"], ["    ", "next"], "i", 4)),
        ("nvim i ⌥⌫ deletes a word", lambda: c("", two, (1, 0), "i$", ["alt+bs"], ["    foo bar ", "next"], "i")),
        ("nvim i ⇧⌘⌫ clears the line", lambda: c("", two, (1, 8), "i", ["cmd+shift+bs"], ["    ", "next"], "i")),
        ("nvim i ⌘A selects all", lambda: c("", two, (1, 8), "i", ["cmd+a"], want_mode="V")),
        ("nvim i ⌘Z undoes typing", lambda: c("", two, (1, 0), "i$", ["type:XY", "cmd+z"], two)),
        ("nvim i ⌘S writes, stays in insert", lambda: c("", ["    written i"], (1, 4), "i", ["cmd+s"], want_mode="i", check=written)),
        ("nvim i ⌘/ toggles comment", lambda: c("", two, (1, 8), "i", ["cmd+slash"], ["    -- foo bar baz", "next"], "i")),
        ("nvim i ⌘] ⌘[ indent/outdent", lambda: c("", two, (1, 8), "i", ["cmd+]", "cmd+["], two, "i")),
        ("nvim i ⌘F → / search", lambda: c("", two, (1, 8), "i", ["cmd+f"], check=cmdline_slash, cleanup=esc_out)),
        # visual mode: "bar" selected (8..10)
        ("nvim v ⌫ deletes selection", lambda: c("", two, (1, 8), "v:10", ["bs"], ["    foo  baz", "next"], "n")),
        ("nvim v ⌘⌫ deletes selection", lambda: c("", two, (1, 8), "v:10", ["cmd+bs"], ["    foo  baz", "next"], "n")),
        ("nvim v ⌘C copies", lambda: c("", two, (1, 8), "v:10", ["cmd+c"], two, "n", want_clip="bar")),
        ("nvim v ⌘X cuts", lambda: c("", two, (1, 8), "v:10", ["cmd+x"], ["    foo  baz", "next"], "n", want_clip="bar")),
        ("nvim v ⇧→ extends", lambda: c("", two, (1, 8), "v:10", ["S-right"], want_sel=(8, 11))),
        ("nvim v ⇧← shrinks", lambda: c("", two, (1, 8), "v:10", ["S-left"], want_sel=(8, 9))),
        ("nvim v ⇧⌘→ extends to line end", lambda: c("", two, (1, 8), "v:10", ["cmd+shift+right"], want_sel=(8, 14))),
        ("nvim v ⇧⌘← extends to first non-blank", lambda: c("", two, (1, 8), "v:10", ["cmd+shift+left"], want_sel=(4, 8))),
        ("nvim v ⌘→ then ⌫ keeps the next line", lambda: c("", two, (1, 8), "v:10", ["cmd+right", "bs"], ["    foo ", "next"], "n")),
        ("nvim v ⌘← then ⌫", lambda: c("", two, (1, 8), "v:10", ["cmd+left", "bs"], ["    ar baz", "next"], "n")),
        ("nvim v ⇧⌘⌫ clears the lines", lambda: c("", two, (1, 8), "v:10", ["cmd+shift+bs"], ["    ", "next"], "i")),
        ("nvim v ⌘] indents, keeps selection", lambda: c("", two, (1, 8), "v:10", ["cmd+]"], want_mode="v",
                                                          check=lambda s: [] if s["lines"][0].startswith("     ") else [f"{s['lines']!r}"])),
        ("nvim v ⌘/ toggles comment", lambda: c("", two, (1, 8), "v:10", ["cmd+slash"], ["    -- foo bar baz", "next"])),
        ("nvim v ⌘A selects all", lambda: c("", two, (1, 8), "v:10", ["cmd+a"], want_mode="V")),
        ("nvim v ⌘S writes", lambda: c("", ["    written v"], (1, 4), "v:6", ["cmd+s"], check=written)),
    ]


def rec_cases():
    def notified():
        v = tmux("show", "-gv", "@notify")
        return [] if "working" in v else [f"no 'working' notification (@notify={v!r})"]

    def not_in_mode(win):
        return lambda: [] if tmux("display", "-p", "-t", f"T:{win}", "#{pane_in_mode}") == "0" else ["entered copy-mode"]

    def in_mode_cleanup(win):
        def f():
            ok = tmux("display", "-p", "-t", f"T:{win}", "#{pane_in_mode}") == "1"
            problems = prompt_closed_by_esc()
            tmux("send-keys", "-t", f"T:{win}", "-X", "cancel")
            return problems + ([] if ok else ["not in tmux copy-mode"])
        return f

    r = rec_case
    cases = [
        ("claude ⌘Z → C-_", lambda: r("claude", ["cmd+z"], b"\x1f")),
        ("claude ⌘← → C-a", lambda: r("claude", ["cmd+left"], b"\x01")),
        ("claude ⌘→ → C-e", lambda: r("claude", ["cmd+right"], b"\x05")),
        ("claude ⌘⌫ → C-u", lambda: r("claude", ["cmd+bs"], b"\x15")),
        ("claude ⇧⌘⌫ idle → Esc Esc", lambda: r("claude", ["cmd+shift+bs"], b"\x1b\x1b")),
        ("claude ⇧⌘⌫ while working → nothing + notify", lambda: r("busy", ["cmd+shift+bs"], b"", notified)),
        ("claude ⌥⌫ passes through", lambda: r("claude", ["alt+bs"], b"\x1b\x7f")),
        ("claude ⇧←/⇧→ pass through", lambda: r("claude", ["S-left", "S-right"], b"\x1b[1;2D\x1b[1;2C")),
        ("claude ⌘F does nothing", lambda: r("claude", ["cmd+f"], b"", not_in_mode("claude"))),
    ]
    for k in ("cmd+a", "cmd+c", "cmd+x", "cmd+shift+z", "cmd+s", "cmd+p", "cmd+slash", "cmd+]", "cmd+[",
              "cmd+shift+left", "cmd+shift+right"):
        cases.append((f"claude {k} sends nothing", lambda k=k: r("claude", [k], b"")))
    cases += [
        ("other ⌘← → Home", lambda: r("other", ["cmd+left"], (b"\x1b[1~", b"\x1b[H", b"\x1bOH"))),
        ("other ⌘→ → End", lambda: r("other", ["cmd+right"], (b"\x1b[4~", b"\x1b[F", b"\x1bOF"))),
        ("other ⌘⌫ → C-u", lambda: r("other", ["cmd+bs"], b"\x15")),
        ("other ⌘A sends nothing", lambda: r("other", ["cmd+a"], b"")),
        ("other ⌘F → copy-mode search", lambda: r("other", ["cmd+f"], b"", in_mode_cleanup("other"))),
    ]
    return cases


def copy_mode_cases():
    def case():
        tmux("copy-mode", "-t", "T:copy")
        for cmd in ("top-line", "start-of-line", "begin-selection", "next-word-end"):
            tmux("send-keys", "-t", "T:copy", "-X", cmd)
        clip_reset()
        before = tmux("display", "-p", "-t", "T:copy", "mode=#{pane_in_mode} sel=#{selection_present} active=#{pane_active}/#{window_active}")
        press("cmd+c")
        problems = []
        if clip() != "alpha":
            problems.append(f"clipboard {clip()!r}, want 'alpha'")
        if tmux("display", "-p", "-t", "T:copy", "#{pane_in_mode}") != "0":
            problems.append(f"still in copy-mode (before ⌘C: {before})")
            tmux("send-keys", "-t", "T:copy", "-X", "cancel")
        return problems
    return [("copy-mode ⌘C copies + exits", case)]


def mouse(events):
    """events: (kind, x, y) with pane-relative 0-based cells; kind = down | drag | up (left button)."""
    left, top = map(int, tmux("display", "-p", "#{pane_left} #{pane_top}").split())
    if tmux("show", "-gv", "status-position") == "top":  # pane_top is window-relative
        st = tmux("show", "-gv", "status")
        top += {"off": 0, "on": 1}.get(st, int(st) if st.isdigit() else 1)
    code = {"down": (0, "M"), "drag": (32, "M"), "up": (0, "m")}
    for kind, x, y in events:
        b, end = code[kind]
        data = f"\x1b[<{b};{x + left + 1};{y + top + 1}{end}".encode()
        tmux("send-keys", "-t", "O", "-H", *[f"{c:02x}" for c in data], sock=OUTER)
        time.sleep(0.15)
    time.sleep(0.4)


def mouse_cases():
    def zsh_at(buf, cur):
        with open(f"{TMP}/zsh.init", "w") as f:
            f.write(f"BUFFER={zq(buf)}; CURSOR={cur}; MARK=0; REGION_ACTIVE=0\n")
        tmux("send-keys", "-t", "T:zsh", "C-x", "r")
        time.sleep(0.3)
        x, y = map(int, tmux("display", "-p", "-t", "T:zsh", "#{cursor_x} #{cursor_y}").split())
        return x - cur, y  # screen x of buffer index 0

    def zsh_click():
        x0, y = zsh_at("echo hello world", 16)
        mouse([("down", x0 + 5, y), ("up", x0 + 5, y)])
        buf, cur = zsh_state()
        return [] if cur == 5 else [f"cursor {cur}, want 5"]

    def zsh_click_multiline(dx, drow, want):
        def f():
            buf = "echo one\necho two\necho three"
            x0, y0 = zsh_at(buf, 0)              # screen cell of buffer index 0 (after the prompt)
            zsh_at(buf, len(buf))                # cursor at the end, like after a paste
            x = x0 + dx if drow == 0 else dx     # rows after the first start at column 0
            mouse([("down", x, y0 + drow), ("up", x, y0 + drow)])
            buf, cur = zsh_state()
            return [] if cur == want else [f"cursor {cur}, want {want}"]
        return f

    def zsh_drag():
        clip_reset()
        x0, y = zsh_at("echo hello world", 16)
        mouse([("down", x0 + 5, y), ("drag", x0 + 7, y), ("drag", x0 + 9, y), ("up", x0 + 9, y)])
        problems = [] if clip() == "hello" else [f"clipboard {clip()!r}, want 'hello'"]
        if tmux("display", "-p", "-t", "T:zsh", "#{pane_in_mode}") != "0":
            problems.append("selection not cleared (still in copy-mode)")
            tmux("send-keys", "-t", "T:zsh", "-X", "cancel")
        return problems

    def nvim_drag():
        nv_send("<C-\\><C-N><Esc>")
        nv_lua('(function() vim.api.nvim_buf_set_lines(0, 0, -1, false, {"    foo bar baz"}) vim.g.kb_clip = nil return 1 end)()')
        a = json.loads(nv_lua("vim.json.encode(vim.fn.screenpos(0, 1, 9))"))
        b = json.loads(nv_lua("vim.json.encode(vim.fn.screenpos(0, 1, 11))"))
        mouse([("down", a["col"] - 1, a["row"] - 1), ("drag", b["col"] - 1, b["row"] - 1), ("up", b["col"] - 1, b["row"] - 1)])
        s = nv_state()
        problems = [] if s["clip"] == "bar" else [f"clipboard {s['clip']!r}, want 'bar'"]
        if s["mode"] != "v":
            problems.append(f"mode {s['mode']!r}, want selection kept ('v')")
        nv_send("<C-\\><C-N><Esc>")
        return problems

    return [("mouse zsh click moves the cursor", lambda: (select("zsh"), zsh_click())[1]),
            ("mouse zsh multi-line click on the first line", lambda: (select("zsh"), zsh_click_multiline(3, 0, 3)())[1]),
            ("mouse zsh multi-line click on a middle line", lambda: (select("zsh"), zsh_click_multiline(5, 1, 14)())[1]),
            ("mouse zsh multi-line click past a line's end", lambda: (select("zsh"), zsh_click_multiline(40, 1, 17)())[1]),
            ("mouse zsh multi-line click on the last line", lambda: (select("zsh"), zsh_click_multiline(2, 2, 20)())[1]),
            ("mouse zsh multi-line click below the buffer is ignored", lambda: (select("zsh"), zsh_click_multiline(2, 4, 28)())[1]),
            ("mouse zsh drag copies + clears", lambda: (select("zsh"), zsh_drag())[1]),
            ("mouse nvim drag copies, stays selected", lambda: (select("nvim"), nvim_drag())[1])]


def ghostty_cases():
    binds = ghostty_text_binds()
    out = []
    for name, trig in GHOSTTY.items():
        def f(trig=trig):
            return [] if trig in binds else [f"ghostty has no text bind for {trig}"]
        out.append((f"ghostty binds {name}", f))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-k", default="")
    args = ap.parse_args()

    binds = ghostty_text_binds()
    KEYS.update(RAW)
    for name, trig in GHOSTTY.items():
        if trig in binds:
            KEYS[name] = binds[trig]

    groups = [(None, ghostty_cases), ("zsh", zsh_cases), ("nvim", nvim_cases), (None, rec_cases),
              ("copy", copy_mode_cases), (None, mouse_cases)]
    setup()
    failed = 0
    total = 0
    try:
        for win, make in groups:
            for name, fn in make():
                if args.k not in name:
                    continue
                if win:
                    select(win)
                elif name.split()[0] in ("claude", "other"):
                    select("busy" if "working" in name else name.split()[0])
                total += 1
                try:
                    problems = fn()
                except Exception as e:  # noqa: BLE001 — report and keep going
                    problems = [f"error: {e!r}"]
                print(("FAIL " if problems else "ok   ") + name + ("".join(f"\n       {p}" for p in problems)))
                failed += bool(problems)
    finally:
        for s in (OUTER, INNER):
            tmux("kill-server", sock=s)
    print(f"\n{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
