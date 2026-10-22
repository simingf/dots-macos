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

# ssh dev box
alias sshdev='ssh sfeng-dev.coder'
alias sshpii='ssh sfeng-pii.coder'

# Launch Claude via the declawd sandbox in --yolo mode.
claude() {
    SHELL=/bin/bash command declawd --yolo "$@"
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
