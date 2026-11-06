-- tmux glue for the prefix g lazygit sidebar (scripts/tmux-lazygit.sh), via pane options:
--   @nvim_repo   repo nvim is looking at (explorer row while the tree is focused, else the
--                file's repo); `follow` switches the sidebar to it
--   @nvim_server this nvim's RPC socket, so lazygit's edit (`k`) opens here
-- Also the RPC entry points tmux scripts call. No-op outside tmux.
local pane = vim.env.TMUX_PANE
if not (vim.env.TMUX and pane) then
	return
end

vim.system({ "tmux", "set-option", "-p", "-t", pane, "@nvim_server", vim.v.servername })

-- tmux-lazygit.sh edit: open file (at line if > 0) in a normal window, out of insert mode.
-- Scheduled so the RPC returns at once.
function _G.TmuxLazygitEdit(file, line)
	vim.schedule(function()
		vim.cmd.stopinsert()
		require("config.tabs").open(file)
		if line > 0 then
			pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
			vim.cmd("normal! zz")
		end
	end)
	return 0
end

-- tmux-nav.sh (prefix m/n/e/i, see nav.lua): TmuxNav returns 1 if nvim moved, 0 at its
-- edge; TmuxNavEnter picks the entry-edge split when tmux moves into this pane.
function _G.TmuxNav(dir)
	return require("config.nav").move(dir) and 1 or 0
end
function _G.TmuxNavEnter(dir)
	require("config.nav").enter(dir)
	return 0
end

local last -- last repo published, so tmux is only poked on a change
local timer = assert(vim.uv.new_timer())

-- repo root (dir holding .git — a dir, or a worktree's file) at or above dir, or nil
local function repo_of(dir)
	local found = vim.fs.find(".git", { upward = true, path = dir, limit = 1 })[1]
	return found and vim.fs.dirname(found) or nil
end

-- the dir nvim is looking at, or nil to keep the published repo (help/terminal/scratch)
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
	-- one tmux call: set the option, then `follow` ($DOTFILES_DIR from tmux's global env)
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
-- unset on quit, or stale options keep steering prefix g / lazygit's edit
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = grp,
	callback = function()
		vim.system({
			"tmux", "set-option", "-p", "-u", "-t", pane, "@nvim_repo", ";",
			"set-option", "-p", "-u", "-t", pane, "@nvim_server",
		}):wait()
	end,
})
