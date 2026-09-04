return {

	-- snacks.explorer: docked file-tree sidebar (replaces neo-tree). Configured as
	-- an extra spec on snacks.nvim — lazy deep-merges it with the main snacks spec
	-- in ui.lua. Behaviors ported 1:1 from the old neo-tree setup:
	-- • replace_netrw: `nvim <dir>` hijacks netrw and opens the tree focused
	--   (snacks wires this on first BufEnter). `nvim <file>` shows it as an
	--   unfocused sidebar via the VimEnter init below. no args → stays lazy.
	-- • watch (source default) auto-refreshes on out-of-band disk changes
	--   (agents, git, mv) — the old use_libuv_file_watcher equivalent.
	-- • hidden+ignored show dotfiles/gitignored dimmed; `H`/`I` toggle at runtime.
	-- • Colemak-DH: `i` (right) opens/expands, `m` (left) collapses; `n`/`e` fall
	--   through to the global down/up remaps for list navigation.
	-- Sidebar sits on the left; width narrowed to 24 (the sidebar preset defaults
	-- to width 40 with a matching min_width that would clamp a smaller width, so
	-- both are overridden below).
	{
		"folke/snacks.nvim",
		opts = {
			explorer = { replace_netrw = true },
			picker = {
				sources = {
					explorer = {
						hidden = true, -- show dotfiles (dimmed)
						ignored = true, -- show gitignored (dimmed)
						layout = { layout = { width = 24, min_width = 24 } },
						win = {
							list = {
								keys = {
									["i"] = "confirm", -- Colemak right: open file / expand dir
									["m"] = "explorer_close", -- Colemak left: collapse dir
									-- `w`: toggle line wrap for the tree (off by default). Tree
									-- indent is real leading text + the list has breakindent, so
									-- wrapped names indent-align under their entry.
									["w"] = function(self)
										vim.wo[self.win].wrap = not vim.wo[self.win].wrap
									end,
								},
							},
						},
					},
				},
			},
		},
		init = function()
			-- file arg(s): show the explorer as an unfocused sidebar once startup
			-- finishes (dir args are handled by replace_netrw; no args stay lazy).
			vim.api.nvim_create_autocmd("VimEnter", {
				once = true,
				callback = function()
					if vim.fn.argc(-1) == 0 then
						return
					end
					local stat = vim.uv.fs_stat(vim.fn.argv(0))
					if stat and stat.type == "directory" then
						return
					end
					local cur = vim.api.nvim_get_current_win()
					Snacks.explorer()
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(cur) then
							pcall(vim.api.nvim_set_current_win, cur)
						end
					end)
				end,
			})

			-- widen the explorer to 40 cols while focused, restore to 24 on leave.
			-- safe against snacks refreshes: split layouts resolve to the live window
			-- width (nvim_win_get_width), not the configured 24, so a direct set
			-- persists exactly like a manual border drag.
			local function explorer_win()
				local p = Snacks.picker.get({ source = "explorer" })[1]
				return p and p.list and p.list.win and p.list.win:valid() and p.list.win.win or nil
			end
			vim.api.nvim_create_autocmd({ "WinEnter", "WinLeave" }, {
				group = vim.api.nvim_create_augroup("explorer_focus_width", { clear = true }),
				callback = function(ev)
					local w = explorer_win()
					if w and w == vim.api.nvim_get_current_win() then
						vim.api.nvim_win_set_width(w, ev.event == "WinEnter" and 40 or 24)
					end
				end,
			})
		end,
		keys = {
			{
				"<leader>`",
				function()
					-- focus toggle: in the tree → jump back to the previous window;
					-- otherwise reveal the current file in the tree (opening if closed).
					local p = Snacks.picker.get({ source = "explorer" })[1]
					if p and p:is_focused() then
						vim.cmd("wincmd p")
					else
						Snacks.explorer.reveal()
					end
				end,
				desc = "focus / leave file tree",
			},
		},
	},

	-- yazi.nvim: launch yazi as a file picker; selecting a file `:edit`s it.
	-- Skipped where yazi isn't installed (e.g. Windows) — `cond` keeps the plugin
	-- in lazy-lock.json so siblings stay byte-identical, but blocks setup at startup.
	{
		"mikavilpas/yazi.nvim",
		version = "*",
		dependencies = { "folke/snacks.nvim" },
		cond = function()
			return vim.fn.executable("yazi") == 1
		end,
		keys = {
			{ "<leader>y", "<cmd>Yazi<cr>", desc = "yazi @ current file" },
			{ "<leader>Y", "<cmd>Yazi cwd<cr>", desc = "yazi @ cwd" },
		},
		opts = {
			open_for_directories = false,
		},
	},
}
