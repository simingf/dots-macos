require("config.options")
require("config.keymaps")
require("config.autocmds")

if vim.env.NVIM_REMOTE then
	return
end

require("config.lazy")
