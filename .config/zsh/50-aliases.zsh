# Shared aliases (mac + linux). Platform-only aliases live in 70-platform.zsh.

# general aliases
alias e='exit'
alias ls='eza --icons=auto --hyperlink=auto'
alias ll='eza -la --git --icons=auto --hyperlink=auto'
alias la='eza -a --icons=auto --hyperlink=auto'
alias l='eza --icons=auto --hyperlink=auto'
alias lt='eza --tree --level=2 -a --git-ignore --icons=auto --hyperlink=auto'
alias mkdir='mkdir -p'
alias npmg='npm list -g --depth 0'

# directory aliases
alias -- -='cd -'
alias ..='cd ..'
alias ...='cd ../..'
alias dots='builtin cd $DOTFILES_DIR'
alias ro='builtin cd ~/git/roblox/'

# config aliases
alias cf="builtin cd ~/.config"
# zsh config
alias zrc="nvim ~/.zshrc"
alias rs="clear && exec zsh"
alias ch=': > ~/.zsh_history && fc -p ~/.zsh_history && clear'
# nvim config
alias nrc="nvim ~/.config/nvim/init.lua"

# competitive programming
alias cpr='make && ./sol'
