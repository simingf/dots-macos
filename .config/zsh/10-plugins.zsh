# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Extra completion dirs — on fpath before compinit (run via atinit in the turbo block).
fpath=($HOME/.docker/completions $HOME/.zfunc $fpath)

# Turbo (deferred) plugin loading — sourced ~after the first prompt (`wait lucid`) so
# startup stays fast. Single sequential block; order honors fzf-tab's rule:
# completions (fpath) → compinit (atinit) → fzf-tab → autosuggestions → highlighting last.
zinit wait lucid for \
    blockf \
        zsh-users/zsh-completions \
    atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
        Aloxaf/fzf-tab \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    zsh-users/zsh-syntax-highlighting

# snippets (deferred too)
zinit wait lucid for \
    OMZP::sudo \
    OMZP::command-not-found

# zsh-syntax-highlighting — rose-pine, iris-forward (reserved words = iris #ceacf6)
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#e0def4'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#eb6f92'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#ceacf6'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#9ccfd8'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#9ccfd8'
ZSH_HIGHLIGHT_STYLES[function]='fg=#9ccfd8'
ZSH_HIGHLIGHT_STYLES[command]='fg=#9ccfd8'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#9ccfd8,italic'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#908caa'
ZSH_HIGHLIGHT_STYLES[path]='fg=#e0def4,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#f6c177'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#f6c177'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#f6c177'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#9ccfd8'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#ebbcba'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#ebbcba'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#6e6a86'

# zsh-autosuggestions ghost text — muted
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6e6a86'
