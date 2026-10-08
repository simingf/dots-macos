# Homebrew
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export HOMEBREW_NO_ENV_HINTS=1
    export NONINTERACTIVE=1
fi

# Environment (shared interactive env -- EDITOR, LS_COLORS, GH_HOST, NVM_DIR,
# ~/.local/bin + skills-cli PATH, DOTFILES_DIR -- lives in .config/zsh/00-env.zsh)
export RIPGREP_CONFIG_PATH=~/.config/ripgrep/rg.conf
export ANI_CLI_PLAYER="$HOME/dots-macos/scripts/iina-cli-activate.sh"
unset GH_TOKEN

# PATH
export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
export PATH="$HOME/.mosaic:$PATH"  # mosaic CLI (Roblox SRE-platform; binary from artifactory, Mac-only work tool)
path+=/Library/TeX/texbin
path+=/Applications/Docker.app/Contents/Resources/bin  # Docker Desktop CLI (docker + credential/kube helpers); appended so it can't shadow brew
path+=$HOME/.docker/bin  # Docker CLI plugins dir (compose/buildx etc.); appended so it can't shadow brew

# Rust (Homebrew's rustup doesn't create ~/.cargo/bin proxies)
if command -v rustup &>/dev/null; then
    export PATH="$HOME/.cargo/bin:$(rustup which cargo 2>/dev/null | xargs dirname 2>/dev/null):$PATH"
fi
