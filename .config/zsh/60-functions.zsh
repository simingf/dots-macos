# Shared functions (mac + linux). Platform-only functions (incl. `claude`, which
# kk and mux-tmux.zsh call) live in 70-platform.zsh.

# yazi wrapper — quitting with `q` lands the shell in yazi's last cwd
y() {
    local cwd tmp="$(mktemp -t yazi-cwd.XXXXXX)"
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

# Lazygit on the meta repos: roblox-notes left, skills right.
metalg() {
    if [[ -z "$_REAL_TMUX" ]]; then
        echo "Not in a tmux session" >&2
        return 1
    fi
    local real_panes=$(tmux list-panes -F '#{@sidebar}' | grep -vc '^1$')
    if [[ "$real_panes" -gt 1 ]]; then
        tmux new-window -n "meta" -c "$HOME/git/roblox/meta/roblox-notes"
        tmux send-keys "lg" Enter
    else
        tmux rename-window "meta"
        tmux send-keys "cd ~/git/roblox/meta/roblox-notes && lg" Enter
    fi
    tmux split-window -h -c "$HOME/git/roblox/meta/skills"
    tmux send-keys "lg" Enter
    "$DOTFILES_DIR/scripts/tmux-even-columns.sh"
}

# Lazygit, one column per repo in ~/git/roblox/active. Main clones only:
# a worktree's .git is a file, so the `.git(/)` dir glob skips it.
activelg() {
    if [[ -z "$_REAL_TMUX" ]]; then
        echo "Not in a tmux session" >&2
        return 1
    fi
    local repos=(~/git/roblox/active/*/.git(/N:h))
    if (( ! $#repos )); then
        echo "No repos in ~/git/roblox/active" >&2
        return 1
    fi
    local real_panes=$(tmux list-panes -F '#{@sidebar}' | grep -vc '^1$')
    if [[ "$real_panes" -gt 1 ]]; then
        tmux new-window -n "active" -c "$repos[1]"
        tmux send-keys "lg" Enter
    else
        tmux rename-window "active"
        tmux send-keys "cd ${(q)repos[1]} && lg" Enter
    fi
    local r
    for r in $repos[2,-1]; do
        tmux split-window -h -c "$r"
        tmux send-keys "lg" Enter
    done
    "$DOTFILES_DIR/scripts/tmux-even-columns.sh"
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

# kk: base fallback — launch claude with flags + prompt (opening files needs a split
# layout, so existing-path args are dropped here). Overridden by
# ~/.config/zsh/mux-tmux.zsh with the full pane layout when sourced inside a
# tmux session (see 95-session.zsh).
kk() {
    emulate -L zsh
    local a
    local -a cflags cprompt
    for a in "$@"; do
        if [[ "$a" == -* ]]; then cflags+=("$a")
        elif [[ ! -e "$a" ]]; then cprompt+=("$a"); fi
    done
    claude "${cflags[@]}" "${cprompt[@]}"
}

# Implementation lives in the skills repo (scripts/pull_repos.sh; portable, worktree-aware).
pullrepos() {
    local script=~/git/roblox/meta/skills/scripts/pull_repos.sh
    if [[ -x "$script" ]]; then
        "$script" "$@"
    else
        echo "pullrepos: $script not found (is the skills repo cloned at ~/git/roblox/meta/skills?)" >&2
        return 1
    fi
}
lsrepos() { pullrepos --local "$@"; }

# goto PR (https://github.rbx.com/Roblox/creator-cu/pull/267/files)
gotopr() {
    local url="$1"
    [[ -z "$url" ]] && {
        echo "usage: gotopr <pr-url>" >&2
        return 1
    }
    local repo=$(echo "$url" | sed 's|.*/\([^/]*\)/pull/.*|\1|')
    local pr=$(echo "$url" | sed 's|.*/pull/\([0-9]*\).*|\1|')
    local org=$(echo "$url" | sed 's|.*/\([^/]*\)/[^/]*/pull/.*|\1|')
    local host=$(echo "$url" | sed 's|https://\([^/]*\)/.*|\1|')

    echo "➡️ PR #$pr in $host/$org/$repo"

    # suppress the chpwd clear+ls while we bounce through dirs; the `always` block
    # resets it even on error/interrupt/return, so it can't leak for the session.
    _suppress_chpwd=1
    {
        mkdir -p ~/git/pr-reviews
        echo "➡️ cd ~/git/pr-reviews/..."
        builtin cd ~/git/pr-reviews/

        if [[ -d "$repo" ]]; then
            echo "➡️ Repo found, fetching latest..."
            builtin cd "$repo" && git fetch --prune
        else
            echo "➡️ Repo not found, cloning $repo..."
            git clone "https://${host}/${org}/${repo}.git"
            builtin cd "$repo"
        fi

        echo "➡️ Checking out PR #$pr..."
        gh pr checkout "$pr"
    } always { _suppress_chpwd=0 }
}

# python
p() {
    if (( $# == 0 )); then
        echo "python: no file given" >&2
        return 1
    fi
    python3 "$@"
}
