# zinit (auto-cloned on first run)
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Extra completion dirs; must be on fpath before compinit (atinit below).
fpath=($HOME/.docker/completions $HOME/.zfunc $fpath)

# Deferred (turbo) loading. Order is fzf-tab's rule:
# completions → compinit → fzf-tab → autosuggestions → syntax-highlighting last.
zinit wait lucid for \
    blockf \
        zsh-users/zsh-completions \
    atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
        Aloxaf/fzf-tab \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    zsh-users/zsh-syntax-highlighting

# OMZ snippets (deferred)
zinit wait lucid for \
    OMZP::sudo \
    OMZP::command-not-found
