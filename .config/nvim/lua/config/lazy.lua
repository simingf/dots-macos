-- bootstrap (from lazy.nvim docs)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- over SSH (dev box) plugins are vendored into a git-tracked dir: never install or
-- check for updates there, or lazy dirties the repo. The Mac is the sole writer.
local env = require("config.env")

require("lazy").setup({
	spec = { { import = "plugins" } },
	install = { missing = not env.IS_SSH },
	checker = { enabled = not env.IS_SSH },
})
