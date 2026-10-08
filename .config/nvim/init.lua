require("config.options")
require("config.keymaps")
require("config.autocmds")

if vim.env.NVIM_REMOTE then
	return
end

require("config.lazy")

-- tmux: publish the repo nvim is looking at for the prefix g lazygit sidebar
require("config.tmux_lazygit")

-- startup health check for the config's fragile plugin-internal / vendored-file
-- dependencies — warns (once, on VeryLazy) if an update silently broke one. See
-- FRAGILE.md; `:ConfigHealth` for the full report.
require("config.healthcheck")
