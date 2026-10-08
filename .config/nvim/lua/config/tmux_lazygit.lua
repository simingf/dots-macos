-- Publish the git repo nvim is "looking at" to tmux, for the prefix g lazygit sidebar
-- (scripts/tmux-lazygit.sh): `toggle` opens on it, `follow` restarts an open sidebar on
-- it when it changes. "Looking at" = the explorer item under the cursor while the
-- snacks explorer list is focused (so moving through the tree across repos switches),
-- else the current file buffer's repo. Stored as the @nvim_repo option on this nvim's
-- tmux pane. No-op outside tmux (so the byte-identical copy is inert on windows).
local pane = vim.env.TMUX_PANE
if not (vim.env.TMUX and pane) then
	return
end

local last -- last repo published, so tmux is only poked on a change
local timer = assert(vim.uv.new_timer())

-- repo root (dir holding .git — a dir, or a worktree's file) at or above dir, or nil
local function repo_of(dir)
	local found = vim.fs.find(".git", { upward = true, path = dir, limit = 1 })[1]
	return found and vim.fs.dirname(found) or nil
end

-- the dir nvim is looking at right now, or nil to leave the published repo as is
-- (help/terminal/scratch buffers, explorer rows outside any repo)
local function current_dir()
	if vim.bo.filetype == "snacks_picker_list" then
		local p = Snacks.picker and Snacks.picker.get({ source = "explorer" })[1]
		local item = p and p:current()
		if not item then
			return nil
		end
		local path = Snacks.picker.util.path(item)
		return item.dir and path or vim.fs.dirname(path)
	end
	if vim.bo.buftype ~= "" then
		return nil
	end
	local name = vim.api.nvim_buf_get_name(0)
	return name ~= "" and vim.fs.dirname(name) or nil
end

local function publish()
	local dir = current_dir()
	local repo = dir and repo_of(dir)
	if not repo or repo == last then
		return
	end
	last = repo
	-- one tmux call: set the option, then let the script restart this window's sidebar
	-- if its repo differs ($DOTFILES_DIR is expanded from tmux's own global env)
	vim.system({
		"tmux", "set-option", "-p", "-t", pane, "@nvim_repo", repo, ";",
		"run-shell", "-b", "$DOTFILES_DIR/scripts/tmux-lazygit.sh follow " .. pane,
	})
end

local grp = vim.api.nvim_create_augroup("tmux_lazygit", { clear = true })
-- debounced: scrolling the tree past several repos only switches lazygit once it settles
vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved" }, {
	group = grp,
	callback = function(ev)
		-- in file buffers only BufEnter can change the repo; cursor moves matter in the tree
		if ev.event == "CursorMoved" and vim.bo.filetype ~= "snacks_picker_list" then
			return
		end
		timer:stop()
		timer:start(250, 0, vim.schedule_wrap(publish))
	end,
})
-- a stale @nvim_repo would keep steering prefix g after nvim quits
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = grp,
	callback = function()
		vim.system({ "tmux", "set-option", "-p", "-u", "-t", pane, "@nvim_repo" }):wait()
	end,
})
