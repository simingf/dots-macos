# Mac-only aliases + functions (dots-linux has its own 70-platform.zsh).
# Anything generic belongs in the shared modules.

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

# updates
alias up='topgrade --yes --no-retry && pullrepos'
alias bup='brew update && brew upgrade && brew cleanup && brew autoremove'
alias zup="zinit self-update && zinit update --all && zinit cclear"

# config aliases
alias grc="nvim ~/.config/ghostty/config"
alias krc="nvim ~/.config/kitty/kitty.conf"
alias arc="nvim ~/.config/aerospace/aerospace.toml"

# ripgrep
alias rg="rg --hyperlink-format=kitty"

# ssh dev box
alias sshdev='ssh sfeng-dev.coder'
alias sshpii='ssh sfeng-pii.coder'

# claude → declawd sandbox, --yolo
claude() {
    SHELL=/bin/bash command declawd --yolo "$@"
}

# k: open in VS Code or Cursor (fzf pick)
k() {
    local editor
    editor=$(printf 'code\ncursor' | fzf --height=4 --prompt='editor: ') || return
    if [[ $# -eq 0 ]]; then
        $editor .
    else
        $editor "$@"
    fi
}

# s: spotify_player. In tmux, viuer's kitty-graphics probe deadlocks (tmux eats the
# reply), so fake TERM to skip it — no album art there.
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
