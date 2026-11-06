# AI agents expect native commands: drop aliases that shadow them (plain ls/rg
# output, no implied mkdir -p, no pwd→pbcopy).
if [[ -n "$AI_AGENT" ]]; then
    unalias ls mkdir pwd rg 2>/dev/null
fi
