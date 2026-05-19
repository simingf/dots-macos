# Prompt
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats '(%b)'

setopt PROMPT_SUBST
PROMPT='zsh|%F{cyan}%~%f%F{yellow}${vcs_info_msg_0_}%f%F{white}>%f '

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
setopt hist_ignore_dups
setopt hist_find_no_dups

# Editor
export EDITOR='nvim'

# GCC colored warnings/errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Color support
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Completions
autoload -Uz compinit && compinit

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# disable automatic window title
DISABLE_AUTO_TITLE="true"

# Execute on Enter
accept-line() {
    if [[ -z $BUFFER ]]; then
        zle -I
        clear && ls --color=auto
    else
        zle ".$WIDGET"
    fi
}
zle -N accept-line

# cd hook: clear+ls on every directory change
chpwd() { clear && ls --color=auto; }

# tmux window title
_tmux_precmd()  { [[ -n "$TMUX" ]] || return; printf '\033k%s\033\\' "$(basename "$PWD")"; }
_tmux_preexec() { [[ -n "$TMUX" ]] || return; printf '\033k%s\033\\' "$1"; }
precmd_functions+=(_tmux_precmd)
preexec_functions+=(_tmux_preexec)

# general aliases
alias e='exit'
alias c='clear && ls'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias rm='rm -r'
alias mkdir='mkdir -p'
alias npmg='npm list -g --depth 0'

# stub pbcopy on linux
pbcopy() { cat > /dev/null; }

# directory aliases
alias ..='cd ..'
alias ...='cd ../..'

# config aliases
alias cf="builtin cd ~/.config"
alias zrc="nvim ~/.zshrc"
alias rs="clear && source ~/.zshrc"
alias ch="rm -f ~/.zsh_history && clear"
alias nrc="nvim ~/.config/nvim/init.lua"

# nvim
alias vim='nvim'
alias v='nvim'

# lazygit
alias lg='echo -ne "\033]0;$(basename $(git rev-parse --show-toplevel 2>/dev/null) || echo "Lazygit")\007" && lazygit'

# tmux
alias trc='nvim ~/.tmux.conf'
alias trs='tmux source ~/.tmux.conf'
alias tl="tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}'"
alias tka='tmux kill-server'

tn() {
  [[ -z "$1" ]] && { echo "usage: tn <name>" >&2; return 1; }
  tmux has-session -t="$1" 2>/dev/null && tmux attach -t "$1" || tmux new -s "$1"
}
ta() {
  local session
  session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | fzf -q "${1:-}" --select-1 --exit-0 --reverse | sed 's/ (attached)$//')
  [[ -z "$session" ]] && return
  tmux attach -t "$session"
}
tk() {
  local session
  session=$(tmux list-sessions -F '#{session_name}#{?session_attached, (attached),}' | fzf -q "${1:-}" --exit-0 --reverse | sed 's/ (attached)$//')
  [[ -z "$session" ]] && return
  tmux kill-session -t "$session"
}

# sl update
sup() {
  echo "➡️ pulling..." && sl pull || return 1
  echo "➡️ rebasing on newest master..." && sl rebase -d master || true
  echo "➡️ restacking..." && sl restack || true
  echo "➡️ submitting prs..." && sl pr submit --stack
}

# claude
alias claude='claude --dangerously-skip-permissions'
alias kk='claude'
alias kkr='claude --resume'

export GH_HOST=github.rbx.com
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/git/skills-cli/bin:$PATH"

# direnv
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# devspace
export AD_USERNAME=sfeng
export VAULT_ENTITY_ID=
export VAULT_ADDR=http://127.0.0.1:8100
