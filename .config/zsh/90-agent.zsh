# AI agents (Claude Code, etc.) shell out to standard commands and expect
# native behavior. Drop aliases that shadow coreutils so `rm` actually deletes
# (not trash), `ls`/`rg` emit plain output (no eza/ripgrep icons+hyperlinks),
# `mkdir` doesn't imply -p, and `pwd` has no pbcopy side effect. Interactive
# shells keep all the aliases above.
if [[ -n "$AI_AGENT" ]]; then
    unalias rm ls mkdir pwd rg 2>/dev/null
fi
