# Mac-only aliases + functions. The one zsh module besides 10-plugins.zsh that
# differs per platform: dots-linux has its own 70-platform.zsh. Everything
# generic goes in the shared modules (50-aliases, 60-functions, 80-tools).

# general aliases
alias f='open .'
alias pwd='pwd | tee >(pbcopy)'
alias icat="kitten icat"
alias top="btop"
alias astro='astroterm --color --constellations --unicode --braille --metadata --city "San Francisco"'

# directory aliases
alias app='builtin cd /Applications/'
alias doc='builtin cd ~/Documents/'
alias dow='builtin cd ~/Downloads/'
alias des='builtin cd ~/Desktop/'
alias dotsl='builtin cd ~/dots-linux'
alias dotsw='builtin cd ~/dots-windows'

# config aliases
# updates everything
alias up='topgrade --yes --no-retry && pullrepos'
# homebrew update
alias bup='brew update && brew upgrade && brew cleanup && brew autoremove'
# zinit update
alias zup="zinit self-update && zinit update --all && zinit cclear"
# ghostty config
alias grc="nvim ~/.config/ghostty/config"
# kitty config
alias krc="nvim ~/.config/kitty/kitty.conf"
# aerospace config
alias arc="nvim ~/.config/aerospace/aerospace.toml"

# ripgrep
alias rg="rg --hyperlink-format=kitty"

# ssh / mosh dev box
alias sshdev='ssh sfeng-dev.coder'
alias moshdev='mosh sfeng-dev.coder'

# Launch Claude via the declawd sandbox in --yolo mode.
claude() {
    SHELL=/bin/bash command declawd --yolo "$@"
}

# Lazygit on all three dots repos side by side.
dotslg() {
    if [[ -z "$_REAL_TMUX" ]]; then
        echo "Not in a tmux session" >&2
        return 1
    fi
    # Count real panes (exclude the agent sidebar) so a lone working pane + sidebar
    # reuses the current window instead of spawning a new one and orphaning the sidebar.
    local real_panes=$(tmux list-panes -F '#{@sidebar}' | grep -vc '^1$')
    if [[ "$real_panes" -gt 1 ]]; then
        tmux new-window -n "dots" -c "$HOME/dots-macos"
        tmux send-keys "lg" Enter
    else
        tmux rename-window "dots"
        tmux send-keys "cd ~/dots-macos && lg" Enter
    fi
    tmux split-window -h -c "$HOME/dots-linux"
    tmux send-keys "lg" Enter
    tmux split-window -h -c "$HOME/dots-windows"
    tmux send-keys "lg" Enter
    # Equalize the three lazygit columns. (Dropped a `tmux-agents.sh sidebar-open` seed here when the
    # agent sidebar was retired — see archive/agent-sidebar/ to restore it.)
    "$DOTFILES_DIR/scripts/tmux-even-columns.sh"
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

# conda (lazy-loaded)
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
