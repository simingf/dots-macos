-- Split navigation shared by <leader>m/n/e/i (config/keymaps.lua) and tmux's prefix
-- m/n/e/i (scripts/tmux-nav.sh → TmuxNav / TmuxNavEnter in config/tmux_lazygit.lua), so
-- nvim splits and tmux panes move as one layout. The explorer counts as one split — its
-- docked box, not the floats drawn over it (wincmd from those floats jumps past the tree).
-- dir is h/j/k/l.
local M = {}

local function explorer()
	return Snacks.picker.get({ source = "explorer" })[1]
end

-- the docked explorer box in this tab, or nil
local function tree_box()
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "snacks_layout_box" then
			return w
		end
	end
end

-- the real split focus is in: the tree's box while the tree (a float) is focused
local function origin()
	local cur = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(cur).relative ~= "" then
		local p = explorer()
		local box = p and p:is_focused() and tree_box()
		return box or cur
	end
	return cur
end

local function focus(w)
	if w == tree_box() then
		explorer():focus("list")
	else
		vim.api.nvim_set_current_win(w)
	end
end

-- a <leader>z zoom is on: it fills nvim and hides the other splits (and closes if focus
-- moves to one), so the zoomed split counts as all of nvim — every direction is the edge
local function zoomed()
	return Snacks.zen.win and Snacks.zen.win:valid()
end

-- move one split toward dir. true = moved inside nvim; false = at nvim's edge (always,
-- while zoomed — tmux moves on to the next pane, and the zoom stays on).
function M.move(dir)
	if zoomed() then
		return false
	end
	local from = origin()
	local to = vim.api.nvim_win_call(from, function()
		return vim.fn.win_getid(vim.fn.winnr(dir))
	end)
	if to == 0 or to == from then
		return false
	end
	focus(to)
	return true
end

-- arriving from another tmux pane while moving toward dir: land on the split at the
-- edge it entered through (moving right → the leftmost split, i.e. the tree)
function M.enter(dir)
	if zoomed() then
		return -- coming back to a zoomed nvim: stay in the zoom
	end
	local opposite = ({ h = "l", l = "h", j = "k", k = "j" })[dir]
	local from = origin()
	local to = vim.api.nvim_win_call(from, function()
		return vim.fn.win_getid(vim.fn.winnr("99" .. opposite))
	end)
	if to ~= 0 and to ~= from then
		focus(to)
	end
end

return M
