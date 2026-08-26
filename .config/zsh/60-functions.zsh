# yazi wrapper — quitting with `q` lands the shell in yazi's last cwd
y() {
    local tmp="$(mktemp -t yazi-cwd.XXXXXX)"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    command rm -f -- "$tmp"
}

# nvim
v() { nvim "${@:-.}"; }

# lazygit
lg() {
    local remote_host
    remote_host=$(git remote get-url origin 2>/dev/null | sed 's|https://\([^/]*\)/.*|\1|; s|git@\([^:]*\):.*|\1|')
    if [[ "$remote_host" == "github.com" ]]; then
        local token
        token=$(GH_TOKEN="" gh auth token --user simingf --hostname github.com 2>/dev/null)
        GH_TOKEN="$token" GH_HOST=github.com lazygit "$@"
    elif [[ "$remote_host" == "github.rbx.com" ]]; then
        local token
        token=$(GH_TOKEN="" gh auth token --user sfeng --hostname github.rbx.com 2>/dev/null)
        GH_TOKEN="$token" GH_HOST=github.rbx.com lazygit "$@"
    else
        lazygit "$@"
    fi
}

dotslg() {
    if [[ -z "$_REAL_TMUX" ]]; then
        echo "Not in a tmux session" >&2
        return 1
    fi
    local pane_count=$(tmux list-panes | wc -l | tr -d ' ')
    if [[ "$pane_count" -gt 1 ]]; then
        tmux new-window -n "dots" -c "$HOME/dots-macos"
        tmux send-keys "lg" Enter
    else
        tmux send-keys "cd ~/dots-macos && lg" Enter
    fi
    tmux split-window -h -c "$HOME/dots-linux"
    tmux send-keys "lg" Enter
    tmux split-window -h -c "$HOME/dots-windows"
    tmux send-keys "lg" Enter
    tmux select-layout even-horizontal
}

# sl update
sup() {
    echo "➡️ pulling..." && sl pull || return 1

    # Reconcile orphans from prior mid-stack amends or interrupted ops.
    # No-op on a clean stack; recovery action when restack has work to do.
    echo "➡️ restacking orphans..." && sl restack || true

    echo "➡️ rebasing on newest master..."
    local out rc
    out=$(sl rebase -d master 2>&1)
    rc=$?
    [[ -n "$out" ]] && echo "$out"
    if [[ $rc -ne 0 ]]; then
        if [[ "$out" == *"nothing to rebase"* ]]; then
            : # benign — already on master, sapling exits non-zero anyway
        elif sl resolve --list 2>/dev/null | grep -q '^U '; then
            _sup_resolve || return 1
        else
            return 1 # already echoed above
        fi
    fi

    # Scope: files modified or added between master and the working copy.
    #   `sl status --rev master` (long form is required — `-r` means --removed
    #   in `sl status`). Don't use `sl files -r 'master::.'`: that lists every
    #   file *tracked at* each rev in the revset, i.e. the whole repo.
    # Tool: `dotnet format whitespace` rather than full `dotnet format`. Full
    #   mode runs analyzer fixers via Roslyn's "Fix All in Solution", which
    #   ignores --include and writes across unincluded files. Whitespace mode
    #   applies only .editorconfig whitespace rules (BOMs, line endings,
    #   indentation, trailing whitespace) and respects --include strictly —
    #   matches the bot's observed behavior.
    echo "➡️ formatting stack-touched files (.editorconfig whitespace)..."
    local stack_files
    stack_files=$(sl status -m -a -n --rev master 2>/dev/null)
    if [[ -n "$stack_files" ]]; then
        echo "  scope: $(echo "$stack_files" | wc -l | tr -d ' ') file(s)"
        echo "$stack_files" | xargs dotnet format whitespace --no-restore --verbosity minimal --include
    else
        echo "  (no stack files)"
    fi

    if [[ -n "$(sl status -m)" ]]; then
        echo "➡️ format diff:"
        sl diff --stat
        echo "➡️ absorbing format changes..."
        # Filter absorb's per-chunk preview; keep only the summary lines.
        sl absorb -a 2>&1 | grep -vE '^[+-][^+-]|^@@|^---|^\+\+\+'
        # Discard any chunks absorb couldn't attribute (changes to lines the
        # user didn't author) so they don't sit in the WC across runs. The
        # bot may still pick those up and commit them on the PR — that's
        # unavoidable without breaking absorb's blame-correctness.
        if [[ -n "$(sl status -m)" ]]; then
            echo "➡️ discarding unabsorbable format debris..."
            sl revert --all
        fi
    fi

    echo "➡️ submitting prs..." && sl pr submit --stack --draft --config github.max-prs-to-create=-1
}

# Walk through each conflicted file in $EDITOR — :wq advances to next.
# Loops until rebase is fully complete: `sl continue` may pause again at a
# subsequent commit's conflict, in which case we re-collect and re-edit.
_sup_resolve() {
    while true; do
        local files
        files=$(sl resolve --list 2>/dev/null | awk '$1 == "U" {print $2}')
        if [[ -z "$files" ]]; then
            # No unresolved files. Rebase may still be paused (e.g., we just
            # marked the last one resolved); call continue to finish it.
            sl continue 2>/dev/null || true
            break
        fi

        echo "➡️ conflicts: opening in ${EDITOR:-nvim} (:wq advances to next)"
        # shellcheck disable=SC2086
        ${EDITOR:-nvim} -- $files </dev/tty || return 1

        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$f"; then
                echo "✗ $f still has conflict markers; aborting" >&2
                echo "  fix manually then: sl resolve --mark $f && sl continue" >&2
                return 1
            fi
            sl resolve --mark "$f" || return 1
        done <<<"$files"

        echo "➡️ continuing rebase..."
        # `sl continue` may pause again at the next commit's conflicts; the
        # outer loop will detect and handle the new unresolved set.
        sl continue || true
    done

    echo "➡️ all conflicts resolved"
    return 0
}

# declawd can launch either Claude or Codex. HerdR honors HERDR_AGENT, so set
# it from the requested mode rather than always marking every run as Claude.
claude() {
    local arg agent=claude
    for arg in "$@"; do
        [[ "$arg" == "--codex" ]] && agent=codex
    done
    HERDR_AGENT="$agent" SHELL=/bin/bash command declawd --yolo "$@"
}

# _kk_recent_nested_repo: print the git repo nested 1–2 levels under $PWD that
# was most recently visited (zoxide frecency order → recency-weighted); if none
# are in the zoxide db, fall back to the newest such repo by .git mtime. Prints
# nothing when the folder has no nested repos.
_kk_recent_nested_repo() {
    emulate -L zsh
    local base="${PWD%/}/" d rel g
    # Primary: zoxide db, highest frecency first → most-recently-visited wins.
    while IFS= read -r d; do
        [[ -n "$d" && "$d" == "$base"* ]] || continue
        rel="${d#$base}"
        ((${#${(s:/:)rel}} <= 2)) || continue # only 1–2 levels below the folder
        [[ -e "$d/.git" ]] && {
            print -r -- "$d"
            return 0
        }
    done < <(zoxide query --list 2>/dev/null)
    # Fallback: newest .git by mtime across depth 1–2 (repo never cd'd into).
    zmodload -F zsh/stat b:zstat 2>/dev/null
    local best="" m
    integer bestm=0
    for g in "$base"*/.git(Nom) "$base"*/*/.git(Nom); do
        m=$(zstat +mtime -- "$g" 2>/dev/null) || continue
        [[ -n "$m" ]] && ((m > bestm)) && {
            bestm=$m
            best="${g:h}"
        }
    done
    [[ -n "$best" ]] && print -r -- "$best"
}

# kk: base fallback — launch claude (flags only; opening files needs a split
# layout). Overridden by ~/.config/zsh/mux-{herdr,tmux}.zsh with the full pane
# layout when sourced inside a herdr or tmux session (see 95-session.zsh).
kk() {
    emulate -L zsh
    local a
    local -a cflags
    for a in "$@"; do [[ "$a" == -* ]] && cflags+=("$a"); done
    claude "${cflags[@]}"
}

# Implementation lives in the babysit-prs skill (portable, worktree-aware) so it
# stays in sync with what /babysit-prs runs. Pass --dry-run to preview.
pullall() {
    local script=~/.claude/skills/babysit-prs/pullall.sh
    if [[ -x "$script" ]]; then
        "$script" "$@"
    else
        echo "pullall: $script not found (is the skills repo symlinked into ~/.claude/skills?)" >&2
        return 1
    fi
}

# goto PR (https://github.rbx.com/Roblox/creator-cu/pull/267/files)
gotopr() {
    local url="$1"
    local repo=$(echo "$url" | sed 's|.*/\([^/]*\)/pull/.*|\1|')
    local pr=$(echo "$url" | sed 's|.*/pull/\([0-9]*\).*|\1|')
    local org=$(echo "$url" | sed 's|.*/\([^/]*\)/[^/]*/pull/.*|\1|')
    local host=$(echo "$url" | sed 's|https://\([^/]*\)/.*|\1|')

    echo "➡️ PR #$pr in $host/$org/$repo"

    _suppress_chpwd=1

    mkdir -p ~/git/pr-reviews
    echo "➡️ cd ~/git/pr-reviews/..."
    builtin cd ~/git/pr-reviews/

    if [ -d "$repo" ]; then
        echo "➡️ Repo found, fetching latest..."
        builtin cd "$repo" && git fetch --prune
    else
        echo "➡️ Repo not found, cloning $repo..."
        git clone "https://${host}/${org}/${repo}.git"
        builtin cd "$repo"
    fi

    echo "➡️ Checking out PR #$pr..."
    gh pr checkout "$pr"

    _suppress_chpwd=0
}

# vscode/cursor
k() {
    local editor
    editor=$(printf 'code\ncursor' | fzf --height=4 --prompt='editor: ') || return
    if [[ $# -eq 0 ]]; then
        $editor .
    else
        $editor "$@"
    fi
}

# python
p() {
    if [[ "$@" == "" ]]; then
        echo "python: no file given"
    else
        python3 "$@"
    fi
}

# spotify_player — viuer's kitty-graphics probe deadlocks under tmux (passthrough is
# one-way; the terminal's reply gets intercepted by tmux and never reaches viuer).
# Override TERM inside tmux so viuer skips the kitty/ghostty path; lose album art there.
s() {
    if [[ -n "$TMUX" ]]; then
        TERM=xterm-256color command spotify_player "$@"
    else
        command spotify_player "$@"
    fi
}
