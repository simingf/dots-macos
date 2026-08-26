# general aliases
alias e='exit'
alias ls='eza --icons=auto --hyperlink=auto'
alias ll='eza -la --git --icons=auto --hyperlink=auto'
alias lt='eza --tree --level=2 -a --git-ignore --icons=auto --hyperlink=auto'
alias f='open .'
alias rm='trash'
alias mkdir='mkdir -p'
alias pwd='pwd | tee >(pbcopy)'
alias npmg='npm list -g --depth 0'
alias icat="kitten icat"
alias top="btop"
alias astro='astroterm --color --constellations --unicode --braille --metadata --city "San Francisco"'

# directory aliases
alias -- -='cd -'
alias ..='cd ..'
alias ...='cd ../..'
alias app='builtin cd /Applications/'
alias doc='builtin cd ~/Documents/'
alias dow='builtin cd ~/Downloads/'
alias des='builtin cd ~/Desktop/'
alias dots='builtin cd ~/dots-macos'
alias dotsl='builtin cd ~/dots-linux'
alias dotsw='builtin cd ~/dots-windows'

# config aliases
# updates everything
alias up='topgrade --yes --no-retry && pullall'
# homebrew update
alias bup='brew update && brew upgrade && brew cleanup && brew autoremove'
# zinit update
alias zup="zinit self-update && zinit update --all && zinit cclear"
alias cf="builtin cd ~/.config"
# zsh config
alias zrc="nvim ~/.zshrc"
alias rs="clear && exec zsh"
alias ch=': > ~/.zsh_history && fc -p ~/.zsh_history && clear'
# ghostty config
alias grc="nvim ~/.config/ghostty/config"
# kitty config
alias krc="nvim ~/.config/kitty/kitty.conf"
# aerospace config
alias arc="nvim ~/.config/aerospace/aerospace.toml"
# nvim config
alias nrc="nvim ~/.config/nvim/init.lua"

# ripgrep
alias rg="rg --hyperlink-format=kitty"

# ssh / mosh dev box
alias sshdev='ssh sfeng-dev.coder'
alias moshdev='mosh sfeng-dev.coder'

# competitive programming
alias cpr='make && ./sol'
