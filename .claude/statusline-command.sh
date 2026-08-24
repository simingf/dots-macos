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

# Total session cost. Claude Code computes this client-side across every API
# call this session (resets on /clear) with current pricing for all model
# families and the 1M-context premium tier, so no per-model price table needed.
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
[ -n "$cost_usd" ] && cost=$(printf '$%.2f' "$cost_usd")

# Blue path, grey git, dim model, green cost
if [ -n "$branch" ] && [ -n "$cost" ]; then
  printf '\033[34m%s\033[0m \033[38;5;244m%s\033[0m  \033[2m%s\033[0m  \033[32m%s\033[0m' \
    "$short_cwd" "$branch" "$model" "$cost"
elif [ -n "$branch" ]; then
  printf '\033[34m%s\033[0m \033[38;5;244m%s\033[0m  \033[2m%s\033[0m' \
    "$short_cwd" "$branch" "$model"
elif [ -n "$cost" ]; then
  printf '\033[34m%s\033[0m  \033[2m%s\033[0m  \033[32m%s\033[0m' \
    "$short_cwd" "$model" "$cost"
else
  printf '\033[34m%s\033[0m  \033[2m%s\033[0m' \
    "$short_cwd" "$model"
fi
