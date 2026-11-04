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
	-- grouped with clear=true so re-sourcing this module (e.g. <leader>r) replaces
	-- the handler instead of stacking a duplicate checktime on every reload.
	group = vim.api.nvim_create_augroup("checktime-on-change", { clear = true }),
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})
-- no swap file for directory buffers. snacks' replace_netrw renames the dir buffer
-- to "" on startup, which creates its swap file — named after the cwd — right then;
-- several nvims started on the same dir at once (kkactive) race for that one name
-- and the losers fail with E303. Registered before lazy, so it runs ahead of snacks.
vim.api.nvim_create_autocmd("BufEnter", {
	desc = "disable swapfile for directory buffers",
	group = vim.api.nvim_create_augroup("dir-noswapfile", { clear = true }),
	callback = function(ev)
		if ev.file ~= "" and vim.fn.isdirectory(ev.file) == 1 then
			vim.bo[ev.buf].swapfile = false
		end
	end,
})
-- wipe empty unnamed buffers once nothing shows them. Every tabnew (<leader>c), the
-- last-tab close and replace_netrw leave a blank [No Name] buffer behind; listed and
-- hidden, they pile up as "[Scratch]" entries in the buffer picker (<leader>w).
vim.api.nvim_create_autocmd("BufHidden", {
	desc = "wipe hidden empty unnamed buffers",
	group = vim.api.nvim_create_augroup("wipe-empty-noname", { clear = true }),
	callback = function(ev)
		vim.schedule(function()
			local b = ev.buf
			if
				vim.api.nvim_buf_is_valid(b)
				and vim.api.nvim_buf_get_name(b) == ""
				and vim.bo[b].buftype == ""
				and not vim.bo[b].modified
				and #vim.fn.win_findbuf(b) == 0
				and vim.api.nvim_buf_line_count(b) == 1
				and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ""
			then
				pcall(vim.api.nvim_buf_delete, b, {})
			end
		end)
	end,
})
