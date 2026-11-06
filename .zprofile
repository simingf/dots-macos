# Homebrew
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export HOMEBREW_NO_ENV_HINTS=1
    export NONINTERACTIVE=1
fi

# Mac-only login env; shared interactive env lives in .config/zsh/00-env.zsh
export RIPGREP_CONFIG_PATH=~/.config/ripgrep/rg.conf
export ANI_CLI_PLAYER="$HOME/dots-macos/scripts/iina-cli-activate.sh"
unset GH_TOKEN

# PATH
export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
export PATH="$HOME/.mosaic:$PATH"  # mosaic CLI (work)
path+=/Library/TeX/texbin
# Docker CLI + plugins: appended so they can't shadow brew
path+=/Applications/Docker.app/Contents/Resources/bin
path+=$HOME/.docker/bin

# Rust (Homebrew's rustup doesn't create ~/.cargo/bin proxies)
if command -v rustup &>/dev/null; then
    export PATH="$HOME/.cargo/bin:$(rustup which cargo 2>/dev/null | xargs dirname 2>/dev/null):$PATH"
fi
