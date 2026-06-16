#!/bin/sh
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name')
model_id=$(echo "$input" | jq -r '.model.id')

# Abbreviate home directory
short_cwd=$(echo "$cwd" | sed "s|^$HOME|~|")

# Git branch + dirty indicator (skip lock files to avoid blocking)
branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
         || GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null)
  [ -n "$dirty" ] && branch="${branch}*"
fi

# Token cost estimate
# Pricing per million tokens (input / cache_write / cache_read / output)
# Sources: Anthropic pricing page
case "$model_id" in
  claude-opus-4*|claude-opus-4-5*)
    in_price=15; cw_price=18.75; cr_price=1.50; out_price=75 ;;
  claude-sonnet-4*|claude-sonnet-4-5*)
    in_price=3; cw_price=3.75; cr_price=0.30; out_price=15 ;;
  claude-haiku-3-5*)
    in_price=0.80; cw_price=1.00; cr_price=0.08; out_price=4 ;;
  claude-haiku-3*)
    in_price=0.25; cw_price=0.30; cr_price=0.03; out_price=1.25 ;;
  *)
    in_price=3; cw_price=3.75; cr_price=0.30; out_price=15 ;;
esac

cost=$(echo "$input" | jq -r --argjson ip "$in_price" --argjson cwp "$cw_price" \
  --argjson crp "$cr_price" --argjson op "$out_price" '
  .context_window.current_usage // empty |
  ((.input_tokens // 0) * $ip
   + (.cache_creation_input_tokens // 0) * $cwp
   + (.cache_read_input_tokens // 0) * $crp
   + (.output_tokens // 0) * $op) / 1000000
  | . * 1000 | round | . / 1000
  | "$" + (tostring | if test("\\.") then . else . + ".0" end)
' 2>/dev/null)

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
