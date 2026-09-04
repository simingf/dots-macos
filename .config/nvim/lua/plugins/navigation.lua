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
	-- Sidebar defaults to width 40, position left — same as before.
	{
		"folke/snacks.nvim",
		opts = {
			explorer = { replace_netrw = true },
			picker = {
				sources = {
					explorer = {
						hidden = true, -- show dotfiles (dimmed)
						ignored = true, -- show gitignored (dimmed)
						win = {
							list = {
								keys = {
									["i"] = "confirm", -- Colemak right: open file / expand dir
									["m"] = "explorer_close", -- Colemak left: collapse dir
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
