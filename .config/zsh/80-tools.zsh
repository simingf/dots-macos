# Shared tool setup (mac + linux). Plugins themselves load in 10-plugins.zsh
# (per-platform); their theme vars below are read whenever they load.

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

# Preview panes for Ctrl-T / Alt-C so they match the fzf-tab completion UI
# (colors/frame inherited from FZF_DEFAULT_OPTS above). eza for dirs, cat for
# files (bat not installed); ctrl-/ toggles the preview. Ctrl-R gets no preview
# — the history row already shows the full command on the line itself.
export FZF_CTRL_T_OPTS="--preview 'if [ -d {} ]; then eza --tree --level=2 --color=always --icons=always --group-directories-first {}; else cat {} 2>/dev/null | head -n 200; fi' --preview-window=right:60% --bind 'ctrl-/:toggle-preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always --icons=always --group-directories-first {}' --preview-window=right:60% --bind 'ctrl-/:toggle-preview'"

# Shell integrations (guarded so a missing tool doesn't error on every startup).
# linux uses the vendored fzf (new enough for --zsh; Debian's 0.44 isn't).
command -v fzf >/dev/null && source <(fzf --zsh)
command -v zoxide >/dev/null && eval "$(zoxide init --cmd cd zsh)"
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

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
