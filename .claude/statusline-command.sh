#!/bin/sh
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name')

# Abbreviate home directory
short_cwd=$(echo "$cwd" | sed "s|^$HOME|~|")

# Git branch + dirty indicator (skip lock files to avoid blocking)
branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
         || GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null)
  [ -n "$dirty" ] && branch="${branch}*"
fi

# Blue path, grey git, dim model
if [ -n "$branch" ]; then
  printf '\033[34m%s\033[0m \033[38;5;244m%s\033[0m  \033[2m%s\033[0m' \
    "$short_cwd" "$branch" "$model"
else
  printf '\033[34m%s\033[0m  \033[2m%s\033[0m' \
    "$short_cwd" "$model"
fi
