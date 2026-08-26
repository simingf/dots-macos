return {

	-- neo-tree: docked VSCode-style file-explorer sidebar. <leader>` focuses it
	-- (opening if closed) and jumps back out when already inside; opening a
	-- directory (`nvim .`) hijacks netrw and shows the tree.
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		cmd = "Neotree",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		init = function()
			-- directory arg (`nvim .`): load neo-tree eagerly so it hijacks netrw
			-- in place. file arg(s): show it as a sidebar (no focus steal) once
			-- startup finishes. no args: stay lazy behind the keymap/cmd.
			local argc = vim.fn.argc(-1)
			if argc == 0 then
				return
			end
			local stat = vim.uv.fs_stat(vim.fn.argv(0))
			if argc == 1 and stat and stat.type == "directory" then
				require("neo-tree")
			else
				vim.api.nvim_create_autocmd("VimEnter", { once = true, command = "Neotree show" })
			end
		end,
		keys = {
			{
				"<leader>`",
				function()
					-- focus toggle: when already in the tree, jump back to the
					-- previous window; otherwise open (if closed) and focus it.
					if vim.bo.filetype == "neo-tree" then
						vim.cmd("wincmd p")
					else
						vim.cmd("Neotree focus")
					end
				end,
				desc = "focus / leave file tree",
			},
		},
		opts = {
			-- when the tree is the only window left (e.g. :q'd the last file),
			-- close it too so nvim quits instead of leaving a fullscreen tree.
			close_if_last_window = true,
			filesystem = {
				-- auto-refresh the tree when files change on disk out-of-band
				-- (agents, git, mv) — off by default, so the sidebar otherwise
				-- only updates on its own actions or a manual `R`.
				use_libuv_file_watcher = true,
				-- show all hidden items (dotfiles + gitignored), displayed dimmed.
				-- `H` toggles them off/on at runtime.
				filtered_items = {
					visible = true,
					hide_dotfiles = false,
					hide_gitignored = false,
				},
			},
			window = {
				position = "left",
				width = 40,
				-- Colemak-DH: `i` (right) opens/expands, `m` (left) collapses.
				-- `n` (down) falls through to the global remap; neo-tree binds `e`
				-- to toggle_auto_expand_width, so release it ("none" skips the
				-- buffer-local map) to let the global `e`→up remap through.
				mappings = {
					["i"] = "open",
					["m"] = "close_node",
					["e"] = "none",
				},
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
