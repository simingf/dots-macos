# Homebrew
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    # If you're using macOS, you'll want this enabled
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Dotfiles dir — referenced by .tmux.conf bindings (mirrored to dots-linux as ~/dots-linux)
export DOTFILES_DIR=~/dots-macos

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
    export EDITOR='vim'
else
    export EDITOR='nvim'
fi

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit snippet OMZP::sudo
zinit snippet OMZP::command-not-found

# Load completions
fpath=($HOME/.docker/completions $HOME/.zfunc $fpath)
autoload -Uz compinit
# Skip the security check / dump rebuild if the cache is < 24h old.
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi
zinit cdreplay -q

# Oh My Posh prompt
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
    eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/zen.toml)"
fi

# Disable DEC mode 2031 (color-scheme change notifications) on every prompt.
# Inner apps (claude code, nvim, etc.) enable it and may not clean up; ghostty
# then re-emits \e[?997;Ps n on tmux session-switch, which leaks "997;1n" into
# shell input via tmux's CSI parser.
autoload -Uz add-zsh-hook
_disable_dec_2031() { printf '\e[?2031l'; }
add-zsh-hook precmd _disable_dec_2031

# Disable mouse-tracking modes on every prompt. Inner apps (vim, htop, remote
# tmux over ssh) enable 1000/1002/1003/1006/1015; if they crash or the ssh
# session dies before sending the matching disable, tmux keeps forwarding click
# bytes to the pane and they land as text in the next shell prompt.
_disable_mouse_tracking() { printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l'; }
add-zsh-hook precmd _disable_mouse_tracking

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# tree / ls colors — also feeds the zstyle list-colors below.
# ANSI named codes (no hex) so colors track the terminal theme (Rose Pine here).
export LS_COLORS='di=01;34:ln=36:or=01;31:ex=01;32:tw=01;34:ow=01;34:pi=33:so=33:bd=33:cd=33:su=01;31:sg=01;31:*.tar=33:*.tgz=33:*.zip=33:*.gz=33:*.bz2=33:*.xz=33:*.7z=33:*.rar=33:*.jpg=35:*.jpeg=35:*.png=35:*.gif=35:*.svg=35:*.mp3=35:*.mp4=35:*.mov=35:*.md=04:*.lock=02:*.log=02:*.bak=02'

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -G $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls -G $realpath'

# clear screen + ls in one atomic write (no fork for clear, no flash gap)
_clear_ls() {
    local out
    out=$(eza --color=always --icons=auto --hyperlink 2>/dev/null)
    printf '\e[H\e[2J\e[3J%s\n' "$out"
}

# Execute on Enter: empty enter → clear+ls
accept-line() {
    if [[ -z $BUFFER ]]; then
        BUFFER=' _clear_ls'
    fi
    zle ".$WIDGET"
}
zle -N accept-line

# cd hook: clear+ls on every directory change
chpwd() { _clear_ls; }

# tmux window title
_tmux_precmd() {
    [[ -n "$TMUX" ]] || return
    [[ $(tmux show -wqv @manual_window_name_set) == 1 ]] && return
    printf '\033k%s\033\\' "$(basename "$PWD")"
}
_tmux_preexec() {
    [[ -n "$TMUX" ]] || return
    [[ $(tmux show -wqv @manual_window_name_set) == 1 ]] && return
    printf '\033k%s\033\\' "$1"
}
precmd_functions+=(_tmux_precmd)
preexec_functions+=(_tmux_preexec)

# pbcopy stderr from failed commands (best-effort: tee subprocess is async,
# so very fast commands' output may not flush before precmd fires).
_zsh_err_buf=$(mktemp -t zsh-err)
trap 'command rm -f "$_zsh_err_buf"' EXIT
exec 2> >(tee -a "$_zsh_err_buf" >&2)
_pbcopy_on_error() {
    local rc=$?
    if ((rc != 0)) && [[ -s "$_zsh_err_buf" ]]; then
        pbcopy <"$_zsh_err_buf"
    fi
    : >"$_zsh_err_buf"
}
precmd_functions+=(_pbcopy_on_error)

# yazi wrapper — quitting with `q` lands the shell in yazi's last cwd
y() {
    local tmp="$(mktemp -t yazi-cwd.XXXXXX)"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    command rm -f -- "$tmp"
}

# general aliases
alias e='exit'
alias ls='eza --icons=auto --hyperlink'
alias ll='eza -la --git --icons=auto --hyperlink'
alias lt='eza --tree --level=2 -a --git-ignore --icons=auto --hyperlink'
alias f='open .'
alias rm='trash'
alias mkdir='mkdir -p'
alias pwd='pwd | tee >(pbcopy)'
alias npmg='npm list -g --depth 0'
alias icat="kitten icat"
alias top="btop"
alias astro='astroterm --color --constellations --unicode --braille --metadata --city "San Francisco"'

# directory aliases
alias -- -='cd -'
alias ..='cd ..'
alias ...='cd ../..'
alias app='builtin cd /Applications/'
alias doc='builtin cd ~/Documents/'
alias dow='builtin cd ~/Downloads/'
alias des='builtin cd ~/Desktop/'
alias dots='builtin cd ~/dots-macos'
alias dotsl='builtin cd ~/dots-linux'
alias dotsw='builtin cd ~/dots-windows'

# config aliases
# updates everything
alias up='topgrade -t -y --no-retry'
# homebrew update
alias bup='brew update && brew upgrade && brew cleanup && brew autoremove'
# zinit update
alias zup="zinit self-update && zinit update --all && zinit cclear"
alias cf="builtin cd ~/.config"
# zsh config
alias zrc="nvim ~/.zshrc"
alias rs="clear && exec zsh"
alias ch="command rm -f ~/.zsh_history && clear"
# ghostty config
alias grc="nvim ~/.config/ghostty/config"
# kitty config
alias krc="nvim ~/.config/kitty/kitty.conf"
# aerospace config
alias arc="nvim ~/.config/aerospace/aerospace.toml"

# nvim
alias nrc="nvim ~/.config/nvim/init.lua"
alias v='nvim'

# lazygit
lg() {
    local name remote_host
    name=$(git rev-parse --show-toplevel 2>/dev/null) && name="lg ($(basename "$name"))" || name="lazygit"
    if [[ -n "$TMUX" ]]; then
        [[ $(tmux show -wqv @manual_window_name_set) != 1 ]] && printf '\033k%s\033\\' "$name"
    else
        printf '\033]0;%s\033\\' "$name"
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
    [[ -z "$TMUX" ]] && printf '\033]0;\033\\'
}

# tmux
alias trc='nvim ~/.tmux.conf'
alias trs="tmux source ~/.tmux.conf"
alias tl="tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}'"
alias tka='tmux kill-server'
# tn <name...>: create new tmux session, or attach if it already exists
tn() {
    local name="$*"
    [[ -z "$name" ]] && {
        echo "usage: tn <name>" >&2
        return 1
    }
    if ! tmux has-session -t="$name" 2>/dev/null; then
        tmux new-session -d -s "$name"
    fi
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    fi
}
# ta [query...]: fuzzy-pick a session to attach to (auto-selects if query matches exactly one)
ta() {
    local session
    session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | fzf -q "$*" --select-1 --exit-0 --reverse | sed 's/ (attached)$//')
    [[ -z "$session" ]] && return
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session"
    else
        tmux attach -t "$session"
    fi
}
# tk [query...]: fuzzy-pick a session to kill (always shows picker, even with exact match)
tk() {
    local session
    session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | fzf -q "$*" --exit-0 --reverse | sed 's/ (attached)$//')
    [[ -z "$session" ]] && return
    tmux kill-session -t "$session"
}
# runall <cmd...>: send <cmd> + Enter to every zsh pane across all tmux sessions
runall() {
    if [[ -z "$*" ]]; then
        echo "usage: runall <command>" >&2
        return 1
    fi
    if ! command -v tmux >/dev/null 2>&1 || ! tmux info >/dev/null 2>&1; then
        echo "runall: no running tmux server" >&2
        return 1
    fi
    local cmd="$*"
    tmux list-panes -a -F '#{pane_current_command} #{pane_id}' |
        awk '$1=="zsh"{print $2}' |
        while read -r pane; do
            tmux send-keys -t "$pane" "$cmd" Enter
        done
}
alias rsa='runall rs'
# rename tmux window to ssh destination; precmd restores on exit
ssh() {
    if [[ -n "$TMUX" ]] && [[ $(tmux show -wqv @manual_window_name_set) != 1 ]]; then
        # Skip option flags to find the destination (first non-option positional).
        local OPTIND=1 OPTARG opt dest
        while getopts ':46AaCfGgKkMNnqsTtVvXxYyB:b:c:D:E:e:F:I:i:J:L:l:m:O:o:p:Q:R:S:W:w:' opt "$@"; do :; done
        dest="${@[OPTIND]}"
        [[ -n "$dest" ]] && printf '\033k%s\033\\' "$dest"
    fi
    command ssh "$@"
}

# ripgrep (modern alternative to grep)
export RIPGREP_CONFIG_PATH=~/.config/ripgrep/rg.conf
alias rg="rg --hyperlink-format=kitty"

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

    echo "➡️ submitting prs..." && sl pr submit --stack
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

# work aliases
alias swarplogin='swarp login sitetest3 && swarp secrets refresh sitetest3'
alias swarprun='swarp run --watch'
alias pps='portpal serve'
alias kk='declawd --no-extra-output --dangerously-skip-permissions'
alias kkr='declawd --no-extra-output --dangerously-skip-permissions --resume'
alias sshdev='ssh sfeng-dev.coder'

pullall() {
  local dir name output branch default stats commits count
  for dir in ~/git/*(/) ~/git/roblox/*/(/); do
    [[ -d "$dir/.git" ]] || continue
    name="${dir/#$HOME/~}"
    branch=$(git -C "$dir" branch --show-current)
    output=$(git -C "$dir" pull --ff-only 2>&1)
    if [[ "$output" == *"no such ref was fetched"* ]]; then
      default=$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
      if [[ -z "$default" ]]; then
        # origin/HEAD not set — pick main or master based on what exists
        if git -C "$dir" show-ref --verify --quiet refs/remotes/origin/main; then
          default=main
        else
          default=master
        fi
      fi
      git -C "$dir" checkout "$default" &>/dev/null
      git -C "$dir" branch -D "$branch" &>/dev/null
      output=$(git -C "$dir" pull --ff-only 2>&1)
      if [[ "$output" == *"Already up to date"* ]]; then
        printf '\e[1;34m%s\e[0m \e[33m%s → %s\e[0m (up to date)\n' "$name" "$branch" "$default"
      else
        printf '\e[1;34m%s\e[0m \e[33m%s → %s\e[0m (pulled)\n' "$name" "$branch" "$default"
      fi
    elif [[ "$output" == *"Already up to date"* ]]; then
      printf '\e[1;34m%s\e[0m \e[36m(%s)\e[0m up to date\n' "$name" "$branch"
    elif [[ "$output" == *"Fast-forward"* || "$output" == *"Updating"* ]]; then
      stats=$(echo "$output" | grep -oE '[0-9]+ files? changed')
      commits=$(echo "$output" | grep -oE '[a-f0-9]+\.\.[a-f0-9]+' | head -1)
      count=$(git -C "$dir" log --oneline "${commits%%..*}..${commits##*..}" 2>/dev/null | wc -l | tr -d ' ')
      printf '\e[1;34m%s\e[0m \e[36m(%s)\e[0m \e[32m+%s commits, %s\e[0m\n' "$name" "$branch" "$count" "$stats"
    else
      printf '\e[1;34m%s\e[0m \e[36m(%s)\e[0m \e[31mfailed\e[0m\n' "$name" "$branch"
    fi
  done
}

# competitive programming
alias cpr='make && ./sol'

# goto PR (https://github.rbx.com/Roblox/creator-cu/pull/267/files)
gotopr() {
    local url="$1"
    local repo=$(echo "$url" | sed 's|.*/\([^/]*\)/pull/.*|\1|')
    local pr=$(echo "$url" | sed 's|.*/pull/\([0-9]*\).*|\1|')
    local org=$(echo "$url" | sed 's|.*/\([^/]*\)/[^/]*/pull/.*|\1|')
    local host=$(echo "$url" | sed 's|https://\([^/]*\)/.*|\1|')

    echo "➡️ PR #$pr in $host/$org/$repo"

    echo "➡️ cd ~/git/roblox/..."
    builtin cd ~/git/roblox/

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

# ani-cli — launching iina-cli from inside tmux opens IINA but doesn't focus it
# (macOS denies frontmost to apps spawned under tmux's session). Wrapper re-activates.
export ANI_CLI_PLAYER="$DOTFILES_DIR/scripts/iina-cli-activate.sh"

# conda (lazy-loaded)
export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
_conda_load() {
    unfunction conda
    __conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    elif [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    fi
    unset __conda_setup
}
conda() { _conda_load && conda "$@"; }

# conda shorthand
c() {
    if [[ "$@" == "" ]]; then
        clear
    elif [[ "$1" == "a" ]]; then
        shift
        conda activate "$@"
    elif [[ "$@" == "d" ]]; then
        conda deactivate
    else
        conda "$@"
    fi
}

export GH_HOST=github.rbx.com
unset GH_TOKEN
# nvm (lazy-loaded)
export NVM_DIR="$HOME/.nvm"
_nvm_load() {
    unfunction nvm node npm npx yarn pnpm 2>/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm() { _nvm_load && nvm "$@"; }
node() { _nvm_load && node "$@"; }
npm() { _nvm_load && npm "$@"; }
npx() { _nvm_load && npx "$@"; }
yarn() { _nvm_load && yarn "$@"; }
pnpm() { _nvm_load && pnpm "$@"; }
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/git/skills-cli/bin:$PATH"

# Reminders MacTeX
path+=/Library/TeX/texbin

# Shell integrations
source <(fzf --zsh)
eval "$(zoxide init --cmd cd zsh)"

# Auto-attach to (or create) tmux session 'dev' on shell startup.
# Skip when already in tmux, in non-interactive shells, or under VSCode/Cursor.
# No `exec`: zsh stays under tmux, so detaching returns to this prompt instead of closing the terminal.
if [[ -z "$TMUX" && $- == *i* && "$TERM_PROGRAM" != "vscode" ]] && command -v tmux >/dev/null 2>&1; then
    tmux has-session -t=dev 2>/dev/null || tmux new-session -d -s dev
    tmux attach -t dev
fi
