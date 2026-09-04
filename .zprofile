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
export LS_COLORS='di=01;38;2;206;172;246:ln=38;2;156;207;216:or=01;38;2;235;111;146:ex=38;2;49;116;143:tw=01;38;2;206;172;246:ow=01;38;2;206;172;246:pi=38;2;246;193;119:so=38;2;246;193;119:bd=38;2;246;193;119:cd=38;2;246;193;119:su=01;38;2;235;111;146:sg=01;38;2;235;111;146:*.tar=38;2;246;193;119:*.tgz=38;2;246;193;119:*.zip=38;2;246;193;119:*.gz=38;2;246;193;119:*.bz2=38;2;246;193;119:*.xz=38;2;246;193;119:*.7z=38;2;246;193;119:*.rar=38;2;246;193;119:*.jpg=38;2;235;188;186:*.jpeg=38;2;235;188;186:*.png=38;2;235;188;186:*.gif=38;2;235;188;186:*.svg=38;2;235;188;186:*.mp3=38;2;235;188;186:*.mp4=38;2;235;188;186:*.mov=38;2;235;188;186:*.md=04:*.lock=38;2;110;106;134:*.log=38;2;110;106;134:*.bak=38;2;110;106;134'
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
