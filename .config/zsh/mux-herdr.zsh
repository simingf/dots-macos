# herdr session module — sourced by .zshrc when HERDR_ENV=1 (inside herdr).
# Defines the herdr-native `kk` layout, overriding the base kk()->claude fallback.
# Relies on _kk_recent_nested_repo() and claude() from .zshrc (defined before the
# source tail).

# _kk_split: herdr pane split (always --no-focus); echo the new pane id, or print
# an error and return non-zero so callers can `|| return` out of kk.
_kk_split() {
    local id
    id=$(herdr pane split "$@" --no-focus | jq -r '.result.pane.pane_id') || return
    [[ -n "$id" && "$id" != null ]] || {
        echo "kk: herdr split failed" >&2
        return 1
    }
    print -r -- "$id"
}

# kk: herdr split — nvim (LEFT) / claude (RIGHT) 50/50. Args starting with - go to
# claude; other args are files opened in nvim (default: the root, as a dir tree).
# Outside herdr, just runs claude. Link nvim↔claude with /ide in the claude pane.
kk() {
    emulate -L zsh
    local a
    local -a cflags files
    for a in "$@"; do [[ "$a" == -* ]] && cflags+=("$a") || files+=("${a:a}"); done
    if [[ "$HERDR_ENV" != 1 ]]; then
        claude "${cflags[@]}"
        return
    fi
    # a git repo roots everything at its top-level; else stay at $PWD
    local root paneroot=$PWD
    if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
        paneroot=$root
    fi
    (( ${#files} )) || files=("$paneroot") # no files → open the root as a dir tree
    # nvim (LEFT) / claude (RIGHT) 50/50. herdr only splits right/down, so open nvim in
    # a right split then swap the two panes — claude stays in the current pane (which
    # --no-focus kept focused), so it lands on the right and keeps focus.
    local right
    right=$(_kk_split --current --direction right --ratio 0.5 --cwd "$paneroot") || return
    # (q@) shell-quotes each file, (j) joins them into one command string for herdr
    herdr pane run "$right" "nvim ${(j: :)${(q@)files}}"
    herdr pane swap --current --direction right # move claude(current) right, nvim left
    (cd "$paneroot" && claude "${cflags[@]}") # claude in the current pane, now on the right
}
