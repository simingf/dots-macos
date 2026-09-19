-- setup code from documentation --
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
-- setup code from documentation --

-- On the dev box (SSH) plugins are vendored read-only into a repo-tracked dir,
-- so lazy must never clone or update: disable install-missing + the update
-- checker, otherwise a stray :Lazy sync re-fetches/regenerates plugin files
-- straight into the git tree and dirties the repo. Local macOS is the sole writer.
local env = require("config.env")

require("lazy").setup({
	spec = { { import = "plugins" } },
}, {
	install = { missing = not env.IS_SSH },
	checker = { enabled = not env.IS_SSH },
})
