# Included by ~/.gitconfig (via includeIf hasconfig) for any repo whose remote
# URL matches https://github.com/Roblox/**. Overrides the default github.com
# account (simingf) with the Roblox public-cloud account. The osxkeychain helper
# is inherited from the [credential "https://github.com"] block in ~/.gitconfig;
# only the account changes, so osxkeychain returns sfeng-roblox's stored PAT.
[credential "https://github.com"]
	username = sfeng-roblox
