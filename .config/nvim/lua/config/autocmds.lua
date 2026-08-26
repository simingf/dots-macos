-- title: show the file name (tail) in the terminal/window title. `%t` is the
-- statusline-format tail, updated automatically — no autocmd needed, and it can't
-- misfire on a filename containing `%`.
vim.opt.title = true
vim.o.titlestring = "%t"

-- highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		local hl = vim.hl or vim.highlight
		hl.on_yank()
	end,
})
-- auto-reload buffers when the file changes on disk (e.g. edits from an agent
-- or git). autoread reloads only on events, so poke :checktime on focus/idle to
-- force the mtime check. Unmodified buffers reload in place; if you have unsaved
-- changes nvim warns instead of clobbering them. Idle refresh is gated by
-- 'updatetime' (default 4000ms) via CursorHold.
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	desc = "reload buffer if the underlying file changed on disk",
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})
