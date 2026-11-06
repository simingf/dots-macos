-- window title = file name (`%t` updates itself and is safe for names containing `%`)
vim.opt.title = true
vim.o.titlestring = "%t"

vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		local hl = vim.hl or vim.highlight
		hl.on_yank()
	end,
})

-- reload files changed on disk (agent/git edits): autoread only acts on events, so
-- poke :checktime on focus/idle (CursorHold = 'updatetime'). Unsaved changes warn instead.
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	desc = "reload buffer if the underlying file changed on disk",
	-- clear=true: re-sourcing (<leader>r) replaces the handler instead of stacking it
	group = vim.api.nvim_create_augroup("checktime-on-change", { clear = true }),
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})

-- no swapfile for directory buffers: snacks' replace_netrw creates one named after the
-- cwd, so nvims started on the same dir at once (kkactive) race for it -> E303.
-- Registered before lazy so it runs ahead of snacks.
vim.api.nvim_create_autocmd("BufEnter", {
	desc = "disable swapfile for directory buffers",
	group = vim.api.nvim_create_augroup("dir-noswapfile", { clear = true }),
	callback = function(ev)
		if ev.file ~= "" and vim.fn.isdirectory(ev.file) == 1 then
			vim.bo[ev.buf].swapfile = false
		end
	end,
})

-- wipe hidden blank [No Name] buffers (left by tabnew, last-tab close, replace_netrw)
-- so they don't pile up as "[Scratch]" in the buffer picker (<leader>w)
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
