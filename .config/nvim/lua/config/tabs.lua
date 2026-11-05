-- Tabpage helpers shared by the tab keys, tab names and pickers (plugins/ui.lua), the
-- explorer (plugins/navigation.lua), LSP jumps (plugins/lsp.lua) and TmuxLazygitEdit
-- (config/tmux_lazygit.lua). Tabs are
-- tabpages, like tmux windows.
local M = {}

-- new tabpage, like tmux ‹pfx›c; carries the explorer sidebar over (unfocused) when
-- this tab has one — the explorer is a split, so a plain tabnew starts without it
function M.new()
	local had_tree = Snacks.picker.get({ source = "explorer" })[1] ~= nil
	vim.cmd("tabnew")
	if had_tree then
		Snacks.explorer({ focus = false })
	end
end

local function normal(w)
	return vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" and vim.api.nvim_win_get_config(w).relative == ""
end

-- the tab's file window: its focused window when that's a normal one, else the last
-- one it focused (`#`), else its first — never the explorer or a float. nil if none.
function M.file_win(tab)
	tab = tab or vim.api.nvim_get_current_tabpage()
	local cur = vim.api.nvim_tabpage_get_win(tab)
	if normal(cur) then
		return cur
	end
	local nr = vim.api.nvim_tabpage_get_number(tab)
	local prev = vim.fn.win_getid(vim.fn.tabpagewinnr(nr, "#"), nr)
	if prev ~= 0 and normal(prev) then
		return prev
	end
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if normal(w) then
			return w
		end
	end
end

-- a split with nothing worth keeping: a fresh unnamed buffer (every new split starts
-- as one, see config/keymaps.lua) or the dir kk opened as a tree
local function empty(w)
	local buf = vim.api.nvim_win_get_buf(w)
	local name = vim.api.nvim_buf_get_name(buf)
	return (name == "" and not vim.bo[buf].modified) or vim.fn.isdirectory(name) == 1
end

-- open a file tmux-style: jump to the split already showing it (any tab), else fill
-- this tab's first empty split (layout order), else open it in a new tab (with the
-- tree, see M.new). Used by the explorer's open (plugins/navigation.lua) and
-- TmuxLazygitEdit.
function M.open(file)
	local path = vim.fn.fnamemodify(file, ":p")
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if normal(w) and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)) == path then
			vim.api.nvim_set_current_win(w)
			return
		end
	end
	local target
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if normal(w) and empty(w) then
			target = w
			break
		end
	end
	if target then
		vim.api.nvim_set_current_win(target)
	else
		M.new()
	end
	vim.cmd("edit " .. vim.fn.fnameescape(path))
end

-- M.open, then put the cursor at pos ({ line, col }, 1-based line, 0-based col) when
-- given — for pickers (grep hits, diagnostics) and LSP jumps (config/lsp.lua)
function M.jump(file, pos)
	M.open(file)
	if pos and pos[1] > 0 then
		vim.cmd("normal! m'") -- so <C-o> returns to where the file was
		pcall(vim.api.nvim_win_set_cursor, 0, { pos[1], math.max(pos[2] or 0, 0) })
		vim.cmd("normal! zz")
	end
end

-- swap the current split's file with the previous (-1) / next (+1) file split, wrapping,
-- and follow it — like tmux ‹pfx›[ / ‹pfx›] (swap-pane). Only file splits take part,
-- so the explorer stays docked on the left.
function M.swap(delta)
	local wins = vim.tbl_filter(normal, vim.api.nvim_tabpage_list_wins(0))
	local cur = vim.api.nvim_get_current_win()
	local i = vim.fn.index(wins, cur) + 1
	if #wins < 2 or i == 0 then
		vim.notify("Only one split!")
		return
	end
	local other = wins[(i - 1 + delta) % #wins + 1]
	local buf_a, buf_b = vim.api.nvim_win_get_buf(cur), vim.api.nvim_win_get_buf(other)
	local view_a = vim.api.nvim_win_call(cur, vim.fn.winsaveview)
	local view_b = vim.api.nvim_win_call(other, vim.fn.winsaveview)
	vim.api.nvim_win_set_buf(cur, buf_b)
	vim.api.nvim_win_set_buf(other, buf_a)
	vim.api.nvim_win_call(cur, function() vim.fn.winrestview(view_b) end)
	vim.api.nvim_win_call(other, function() vim.fn.winrestview(view_a) end)
	vim.api.nvim_set_current_win(other)
end

-- move the current split into its own new tab, like tmux ‹pfx›! (break-pane); the
-- new tab gets the tree when this one has it (see M.new)
function M.break_out()
	local wins = vim.tbl_filter(normal, vim.api.nvim_tabpage_list_wins(0))
	if #wins < 2 or not normal(0) then
		vim.notify("Only one split!")
		return
	end
	local had_tree = Snacks.picker.get({ source = "explorer" })[1] ~= nil
	vim.cmd("wincmd T")
	if had_tree then
		Snacks.explorer({ focus = false })
	end
end

-- closing a split/tab closes its files too, like killing a tmux pane: delete each of
-- bufs that's now shown nowhere, so the buffer list (<leader>w) is what's on screen —
-- unsaved ones included, once settle_unsaved has saved or discarded them. Closed files
-- remain in recent files (<leader>tr).
local function drop_unshown(bufs)
	for _, b in ipairs(bufs) do
		if
			vim.api.nvim_buf_is_valid(b)
			and vim.bo[b].buftype == ""
			and not vim.bo[b].modified
			and #vim.fn.win_findbuf(b) == 0
		then
			pcall(vim.api.nvim_buf_delete, b, {})
		end
	end
end

-- before closing wins: for each unsaved file in them that no other window shows, ask
-- Save / Don't Save / Cancel (like `:confirm quit`). Don't Save discards it, so
-- drop_unshown can close it. false = cancelled (or the save failed): don't close.
local function settle_unsaved(wins)
	local closing = {}
	for _, w in ipairs(wins) do
		closing[w] = true
	end
	for _, w in ipairs(wins) do
		local b = vim.api.nvim_win_get_buf(w)
		local elsewhere = vim.tbl_filter(function(o)
			return not closing[o]
		end, vim.fn.win_findbuf(b))
		if vim.bo[b].modified and vim.bo[b].buftype == "" and #elsewhere == 0 then
			local name = vim.api.nvim_buf_get_name(b)
			local label = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.")
			local choice = vim.fn.confirm(("Save changes to %s?"):format(label), "&Save\n&Don't Save\n&Cancel", 1, "Question")
			if choice == 1 then
				if name == "" then
					name = vim.fn.input("Save as: ", "", "file")
					if name == "" then
						return false
					end
				end
				-- silent: the "written" message after the dialog would stop on a hit-enter prompt
				local ok, err = pcall(vim.api.nvim_buf_call, b, function()
					vim.cmd("silent write " .. vim.fn.fnameescape(name))
				end)
				if not ok then
					vim.notify(err, vim.log.levels.ERROR)
					return false
				end
			elseif choice == 2 then
				vim.bo[b].modified = false
			else
				vim.cmd.redraw() -- clear the dialog line
				return false
			end
			vim.cmd.redraw()
		end
	end
	return true
end

-- close a tabpage (default: the current one), like tmux ‹pfx›k. The last tab can't
-- close, so it drops its buffer via Snacks instead — that keeps the window layout
-- (plain `bdelete` collapses the edit window, letting the explorer fill the screen).
function M.close(tab)
	tab = tab or vim.api.nvim_get_current_tabpage()
	if #vim.api.nvim_list_tabpages() > 1 then
		local wins = vim.api.nvim_tabpage_list_wins(tab)
		if not settle_unsaved(wins) then
			return
		end
		local bufs = vim.tbl_map(vim.api.nvim_win_get_buf, wins)
		vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tab))
		drop_unshown(bufs)
	else
		-- ask with the same dialog first, so Snacks then finds nothing unsaved
		if settle_unsaved({ vim.api.nvim_get_current_win() }) then
			Snacks.bufdelete()
		end
	end
end

-- close the current split, like tmux ‹pfx›x; the tab's last file split closes the
-- tab, as tmux closes a window with its last pane
function M.close_split()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	if #vim.tbl_filter(normal, vim.api.nvim_tabpage_list_wins(0)) < 2 then
		M.close()
		return
	end
	if not settle_unsaved({ win }) then
		return
	end
	local ok, err = pcall(vim.cmd.close)
	if not ok then
		vim.notify(err, vim.log.levels.WARN)
		return
	end
	drop_unshown({ buf })
end

return M
