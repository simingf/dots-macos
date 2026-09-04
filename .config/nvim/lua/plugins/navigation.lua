return {

	-- snacks.explorer: docked file-tree sidebar (replaces neo-tree). Configured as
	-- an extra spec on snacks.nvim — lazy deep-merges it with the main snacks spec
	-- in ui.lua. Behaviors ported 1:1 from the old neo-tree setup:
	-- • replace_netrw: `nvim <dir>` hijacks netrw and opens the tree focused
	--   (snacks wires this on first BufEnter). `nvim <file>` shows it as an
	--   unfocused sidebar via the VimEnter autocmd in opts below. no args → lazy.
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
		-- opts is a *function*, and our startup autocmds are armed here rather than in
		-- `init`. snacks is split across fragments (ui.lua, ai.lua, here) and lazy
		-- keeps only ONE `init`/`config` per plugin (last fragment wins — ui.lua's),
		-- so an `init` here silently never runs. opts-functions instead CHAIN across
		-- fragments and run when the plugin loads; snacks is lazy=false, so that
		-- happens during startup, before VimEnter fires — early enough to register it.
		opts = function(_, opts)
			local grp = vim.api.nvim_create_augroup("snacks_explorer", { clear = true })

			-- `nvim <file>`: show the explorer as an unfocused sidebar (focus stays on
			-- the file). dir args are handled by replace_netrw; no args stay lazy.
			-- `focus = false` opens the picker without it grabbing focus (honored in
			-- picker:show) — cleaner than opening focused then racing to refocus.
			vim.api.nvim_create_autocmd("VimEnter", {
				group = grp,
				once = true,
				callback = function()
					if vim.fn.argc(-1) == 0 then
						return
					end
					local stat = vim.uv.fs_stat(vim.fn.argv(0))
					if stat and stat.type == "directory" then
						return
					end
					Snacks.explorer({ focus = false })
				end,
			})

			-- widen the explorer to 40 cols while focused, back to 24 on leave. the
			-- visible list is a float sized to a hidden root split, so we resize the
			-- ROOT (setting the float does nothing to the column) and let the float
			-- follow; snacks resolves splits to the live root width on refresh, so it
			-- persists. one persistent autocmd that self-locates the explorer picker,
			-- so it spans close/reopen. focus is read off the float, width set on root.
			vim.api.nvim_create_autocmd({ "WinEnter", "WinLeave" }, {
				group = grp,
				callback = function(ev)
					local p = Snacks.picker and Snacks.picker.get({ source = "explorer" })[1]
					if not (p and p.list and p.list.win and p.list.win:valid()) then
						return
					end
					if p.list.win.win ~= vim.api.nvim_get_current_win() then
						return
					end
					local root = p.layout and p.layout.root and p.layout.root.win
					if root and vim.api.nvim_win_is_valid(root) then
						vim.api.nvim_win_set_width(root, ev.event == "WinEnter" and 40 or 24)
					end
				end,
			})

			return vim.tbl_deep_extend("force", opts, {
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
										-- `W`: toggle line wrap for the tree (off by default), matching
										-- the H/I toggle style. Tree indent is real leading text + the
										-- list has breakindent, so wrapped names indent-align.
										["W"] = function(self)
											vim.wo[self.win].wrap = not vim.wo[self.win].wrap
										end,
									},
								},
							},
						},
					},
				},
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
