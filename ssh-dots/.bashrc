# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Prompt with git branch
parse_git_branch() {
  git branch 2>/dev/null | grep '*' | sed 's/* //'
}
PS1='bash|\[\e[36m\]\w\[\e[0m\]\[\e[33m\]$(b=$(parse_git_branch); [ -n "$b" ] && echo "($b)")\[\e[0m\]> '

# History
HISTCONTROL=ignoreboth
HISTSIZE=5000
HISTFILESIZE=10000
shopt -s histappend
shopt -s checkwinsize

# Editor
export EDITOR='nvim'

# GCC colored warnings/errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# make less handle non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# cd override: always clear+ls on directory change
cd() { builtin cd "$1" && clear && ls; }

# tmux window title (precmd equivalent via PROMPT_COMMAND)
_tmux_precmd() { [[ -n "$TMUX" ]] && printf '\033k%s\033\\' "$(basename "$PWD")"; }

# Empty Enter: clear+ls (detects empty enter by checking if history number advanced)
_prev_hist_n=-1
_check_empty_enter() {
    local n
    n=$(HISTTIMEFORMAT= history 1 2>/dev/null | awk '{print $1; exit}')
    : "${n:=0}"
    if (( n <= _prev_hist_n )); then
        clear && ls --color=auto
    else
        _prev_hist_n=$n
    fi
}

PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_tmux_precmd; _check_empty_enter"

# general aliases
alias e='exit'
alias c='clear && ls'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias rm='rm -r'
alias mkdir='mkdir -p'
alias npmg='npm list -g --depth 0'

# fix pbcopy on linux
pbcopy() { cat > /dev/null; }

# directory aliases
alias ..='cd ..'
alias ...='cd ../..'

# Config aliases
alias rs='source ~/.bashrc'
alias brc='nvim ~/.bashrc'
alias cf="builtin cd ~/.config"
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
command -v direnv &>/dev/null && eval "$(direnv hook bash)"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# devspace
export AD_USERNAME=sfeng
export VAULT_ENTITY_ID=
export VAULT_ADDR=http://127.0.0.1:8100
