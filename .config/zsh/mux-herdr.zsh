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

# kk: herdr split — claude (LEFT pane), nvim (RIGHT column), plain terminal in the
# bottom ~30%. In a git repo — or a folder with git repos nested ≤2 deep — it's a
# 3-pane 35/35/30 split adding lazygit (terminal under lazygit, nvim full-height);
# otherwise claude/nvim 50/50 (terminal under nvim). Args starting with - go to
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
    # roots: a git repo puts everything at its top-level; else nvim/term/claude stay
    # at $PWD and lazygit (if a repo is nested ≤2 deep) opens the most-recent one.
    local root paneroot=$PWD lgroot
    if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
        paneroot=$root lgroot=$root
    else
        lgroot=$(_kk_recent_nested_repo)
    fi
    (( ${#files} )) || files=("$paneroot") # no files → open the root as a dir tree
    local right lg
    if [[ -n "$lgroot" ]]; then
        # 0.538 splits the 65% right region into nvim 35% / lazygit 30%; terminal under lazygit
        right=$(_kk_split --current --direction right --ratio 0.35 --cwd "$paneroot") || return
        lg=$(_kk_split "$right" --direction right --ratio 0.538 --cwd "$lgroot") || return
        _kk_split "$lg" --direction down --ratio 0.70 --cwd "$paneroot" >/dev/null || return
        herdr pane run "$lg" "lazygit"
    else
        right=$(_kk_split --current --direction right --ratio 0.5 --cwd "$paneroot") || return
        _kk_split "$right" --direction down --ratio 0.70 --cwd "$paneroot" >/dev/null || return
    fi
    # (q@) shell-quotes each file, (j) joins them into one command string for herdr
    herdr pane run "$right" "nvim ${(j: :)${(q@)files}}"
    (cd "$paneroot" && claude "${cflags[@]}") # claude in the left pane, rooted at paneroot
}
