# Shared git config: pull/push defaults + rose-pine colors (iris-forward).
# Byte-identical across dots-macos / dots-linux / dots-windows; each platform's
# global config pulls it in via [include]. Global ignores live next to it in
# ~/.config/git/ignore (git's default excludesfile -- no config needed).
[pull]
	rebase = false
[push]
	autoSetupRemote = true
[color]
	ui = auto
[color "diff"]
	meta = "#908caa"
	frag = "#ceacf6"
	old = "#eb6f92"
	new = "#9ccfd8"
	commit = "#f6c177"
	whitespace = "#eb6f92 reverse"
[color "status"]
	header = "#908caa"
	added = "#9ccfd8"
	changed = "#f6c177"
	untracked = "#6e6a86"
	branch = "#ceacf6"
[color "branch"]
	current = "#ceacf6"
	local = "#e0def4"
	remote = "#9ccfd8"
[color "decorate"]
	branch = "#ceacf6"
	remoteBranch = "#9ccfd8"
	tag = "#f6c177"
	HEAD = "#ceacf6"
