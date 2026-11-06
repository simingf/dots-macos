# Shared functions (mac + linux). Platform-only ones (incl. `claude`) live in 70-platform.zsh.

# yazi: quitting with `q` lands the shell in yazi's last cwd
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

# --- lazygit ---
# lg: lazygit with the per-host GH token. In tmux, overlays lazygit-tmux-edit.yml
# so edit (`k`) opens in this window's nvim.
lg() {
    local remote_host
    if [[ -n $TMUX && -z $LG_CONFIG_FILE ]]; then
        local base=~/.config/lazygit/config.yml
        [[ -f ~/Library/Application\ Support/lazygit/config.yml ]] && base=~/Library/Application\ Support/lazygit/config.yml
        local -x LG_CONFIG_FILE="$base,$DOTFILES_DIR/scripts/lazygit-tmux-edit.yml"
    fi
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

# metalg: lazygit on the meta repos (roblox-notes | skills).
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

# dotslg: lazygit, one column per dots repo cloned on this host.
dotslg() {
    if [[ -z "$_REAL_TMUX" ]]; then
        echo "Not in a tmux session" >&2
        return 1
    fi
    local repos=(~/dots-{macos,linux,windows}/.git(/N:h))
    if (( ! $#repos )); then
        echo "No dots repos in ~" >&2
        return 1
    fi
    local real_panes=$(tmux list-panes -F '#{@sidebar}' | grep -vc '^1$')
    if [[ "$real_panes" -gt 1 ]]; then
        tmux new-window -n "dots" -c "$repos[1]"
        tmux send-keys "lg" Enter
    else
        tmux rename-window "dots"
        tmux send-keys "cd ${(q)repos[1]} && lg" Enter
    fi
    local r
    for r in $repos[2,-1]; do
        tmux split-window -h -c "$r"
        tmux send-keys "lg" Enter
    done
    "$DOTFILES_DIR/scripts/tmux-even-columns.sh"
}

# activelg: lazygit, one column per repo in ~/git/roblox/active. `.git(/)` skips
# worktrees (their .git is a file).
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

# --- sapling ---
# sup: pull, rebase the stack on master, whitespace-format touched files, submit.
sup() {
    echo "➡️ pulling..." && sl pull || return 1

    # Reconcile orphans from mid-stack amends / interrupted ops (no-op when clean).
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

    # Scope: files changed since master. `--rev` long form: in `sl status`, `-r` = --removed.
    # `format whitespace`, not full `dotnet format`: analyzer fixers ignore --include
    # and touch the whole solution.
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
        # Keep only absorb's summary lines.
        sl absorb -a 2>&1 | grep -vE '^[+-][^+-]|^@@|^---|^\+\+\+'
        # Drop chunks absorb can't attribute (lines you didn't author) so they
        # don't linger in the working copy.
        if [[ -n "$(sl status -m)" ]]; then
            echo "➡️ discarding unabsorbable format debris..."
            sl revert --all
        fi
    fi

    echo "➡️ submitting prs..." && sl pr submit --stack --draft --config github.max-prs-to-create=-1
}

# _sup_resolve: edit each conflicted file in $EDITOR (:wq → next), repeating until
# the rebase completes (`sl continue` may pause at a later commit's conflicts).
_sup_resolve() {
    while true; do
        local files
        files=$(sl resolve --list 2>/dev/null | awk '$1 == "U" {print $2}')
        if [[ -z "$files" ]]; then
            # Rebase may still be paused after the last resolve.
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
        sl continue || true
    done

    echo "➡️ all conflicts resolved"
    return 0
}

# --- misc ---
# kk fallback: claude with flags + prompt (path args dropped). Overridden by mux-tmux.zsh.
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

# pullrepos / lsrepos: wrap the skills repo's scripts/pull_repos.sh.
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

# gotopr <pr-url>: clone/fetch into ~/git/pr-reviews and check out the PR.
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

    # Mute chpwd's clear+ls; `always` resets it even on error/interrupt.
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

# p: python3, but refuse to open a REPL.
p() {
    if (( $# == 0 )); then
        echo "python: no file given" >&2
        return 1
    fi
    python3 "$@"
}

# cpterm: copy the previous command + its output (scrollback back to the last
# `❯ ` / `zsh|` prompt). tmux-only: needs capture-pane.
cpterm() {
    if [[ -z $TMUX ]]; then
        echo "Not in a tmux session" >&2
        return 1
    fi
    local lines=("${(@f)$(tmux capture-pane -pJ -S - -t "$TMUX_PANE")}") i
    for (( i = $#lines - 1; i > 0; i-- )); do
        [[ $lines[i] == ('❯ '|'zsh|')* ]] && break
    done
    if (( ! i )); then
        echo "No previous prompt in scrollback" >&2
        return 1
    fi
    print -rl -- "${(@)lines[i,-2]}" | pbcopy
    "$DOTFILES_DIR/scripts/tmux-notify.sh" "copied $(( $#lines - i )) lines"
}
