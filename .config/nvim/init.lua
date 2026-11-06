require("config.options")
require("config.keymaps")
require("config.autocmds")

if vim.env.NVIM_REMOTE then
	return
end

require("config.lazy")

-- publish nvim's repo/socket to tmux for the prefix g lazygit sidebar
require("config.tmux_lazygit")

-- warn if a plugin update broke a fragile assumption (FRAGILE.md, :ConfigHealth)
require("config.healthcheck")
