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
