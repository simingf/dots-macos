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

# nvm (lazy-loaded)
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

# fzf — rose-pine, iris-forward (pointer/prompt/marker/border = iris #ceacf6)
export FZF_DEFAULT_OPTS="--color=fg:#908caa,bg:-1,hl:#ceacf6,fg+:#e0def4,bg+:#26233a,hl+:#ceacf6,border:#ceacf6,header:#908caa,info:#6e6a86,spinner:#f6c177,pointer:#ceacf6,marker:#ceacf6,prompt:#ceacf6,gutter:-1"

# Shell integrations (guarded so a missing tool doesn't error on every startup)
command -v fzf >/dev/null && source <(fzf --zsh)
command -v zoxide >/dev/null && eval "$(zoxide init --cmd cd zsh)"
