-- Browser preview of the current buffer: markdown → markdown-preview, else (html/svg/…)
-- → live-preview. Used by the explorer `o` key and <leader>p.
local M = {}

function M.current()
	local path = vim.api.nvim_buf_get_name(0)
	local md = path:match("%.md$") or path:match("%.markdown$")
	if md and vim.fn.exists(":MarkdownPreview") == 2 then
		vim.cmd("MarkdownPreview")
	else
		vim.cmd("LivePreview start " .. vim.fn.fnameescape(path))
	end
end

return M
