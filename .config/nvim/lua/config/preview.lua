-- Shared browser-preview router. `.md`/`.markdown` → markdown-preview (rose-pine
-- themed); everything else (html/svg/…) → live-preview. Operates on the current
-- buffer, so callers open the target first. Used by the snacks-explorer `o` key
-- (plugins/navigation.lua) and the <leader>p keymap (config/keymaps.lua).
local M = {}

function M.current()
	local path = vim.api.nvim_buf_get_name(0)
	local md = path:match("%.md$") or path:match("%.markdown$")
	if md and vim.fn.exists(":MarkdownPreview") == 2 then
		vim.cmd("MarkdownPreview") -- rose-pine themed browser md
	else
		vim.cmd("LivePreview start " .. vim.fn.fnameescape(path)) -- html/svg (user-styled)
	end
end

return M
