# Homebrew
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export HOMEBREW_NO_ENV_HINTS=1
    export NONINTERACTIVE=1
fi

# Environment
export DOTFILES_DIR=~/dots-macos
if [[ -n $SSH_CONNECTION ]]; then
    export EDITOR='vim'
else
    export EDITOR='nvim'
fi
export LS_COLORS='di=01;34:ln=36:or=01;31:ex=01;32:tw=01;34:ow=01;34:pi=33:so=33:bd=33:cd=33:su=01;31:sg=01;31:*.tar=33:*.tgz=33:*.zip=33:*.gz=33:*.bz2=33:*.xz=33:*.7z=33:*.rar=33:*.jpg=35:*.jpeg=35:*.png=35:*.gif=35:*.svg=35:*.mp3=35:*.mp4=35:*.mov=35:*.md=04:*.lock=02:*.log=02:*.bak=02'
export RIPGREP_CONFIG_PATH=~/.config/ripgrep/rg.conf
export ANI_CLI_PLAYER="$DOTFILES_DIR/scripts/iina-cli-activate.sh"
export GH_HOST=github.rbx.com
unset GH_TOKEN
export NVM_DIR="$HOME/.nvm"

# PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/git/skills-cli/bin:$PATH"
export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
path+=/Library/TeX/texbin

# Rust (Homebrew's rustup doesn't create ~/.cargo/bin proxies)
if command -v rustup &>/dev/null; then
    export PATH="$HOME/.cargo/bin:$(rustup which cargo 2>/dev/null | xargs dirname 2>/dev/null):$PATH"
fi
