# Interactive-shell env shared by mac + linux. Lives here, not in .zprofile: the
# linux box's shells and tmux panes are non-login, so they never source
# .zprofile. mac's .zprofile keeps only Mac-only login env (homebrew, conda...).

# Repo root, resolved from this file's real path (~/.config/zsh is a symlink
# into ~/dots-<platform>/.config/zsh), so no per-platform branch is needed.
export DOTFILES_DIR=${${(%):-%x}:A:h:h:h}

# Prepend user bins; -U drops later duplicates (a login shell may have added them).
path=(~/.local/bin ~/git/skills-cli/bin $path)
typeset -U path

if [[ -n $SSH_CONNECTION ]]; then
    export EDITOR='vim'
else
    export EDITOR='nvim'
fi
export GH_HOST=github.rbx.com
export NVM_DIR="$HOME/.nvm"

# Rose-pine LS_COLORS (source of truth mirrored by yazi + nvim, see THEME.md):
# themes ls/eza and zsh completion's list-colors (30-interactive.zsh).
export LS_COLORS='di=01;38;2;206;172;246:ln=38;2;156;207;216:or=01;38;2;235;111;146:ex=38;2;49;116;143:tw=01;38;2;206;172;246:ow=01;38;2;206;172;246:pi=38;2;246;193;119:so=38;2;246;193;119:bd=38;2;246;193;119:cd=38;2;246;193;119:su=01;38;2;235;111;146:sg=01;38;2;235;111;146:*.tar=38;2;246;193;119:*.tgz=38;2;246;193;119:*.zip=38;2;246;193;119:*.gz=38;2;246;193;119:*.bz2=38;2;246;193;119:*.xz=38;2;246;193;119:*.7z=38;2;246;193;119:*.rar=38;2;246;193;119:*.jpg=38;2;235;188;186:*.jpeg=38;2;235;188;186:*.png=38;2;235;188;186:*.gif=38;2;235;188;186:*.svg=38;2;235;188;186:*.mp3=38;2;235;188;186:*.mp4=38;2;235;188;186:*.mov=38;2;235;188;186:*.md=04:*.lock=38;2;110;106;134:*.log=38;2;110;106;134:*.bak=38;2;110;106;134'
