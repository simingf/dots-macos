return {

	-- snacks.explorer: docked file tree on the left (fragment merged with ui.lua's snacks spec).
	-- `nvim <dir>` opens it focused (replace_netrw), `nvim <file>` unfocused (VimEnter
	-- below), no args: not at all. Dotfiles/gitignored shown dimmed (H/I toggle).
	-- Colemak: i opens/expands, m collapses, n/e move.
	{
		"folke/snacks.nvim",
		-- autocmds live in an opts *function*: lazy keeps one init/config per plugin (ui.lua's
		-- wins), but opts functions chain, and run at startup (lazy=false) before VimEnter
		opts = function(_, opts)
			local grp = vim.api.nvim_create_augroup("snacks_explorer", { clear = true })

			-- force-refresh git icons (`R`, FocusGained): macOS FSEvents misses git's
			-- index.lock→index rename, and `u` doesn't bust explorer/git.lua's 15-min CACHE_TTL
			local function refresh_git()
				local p = Snacks.picker and Snacks.picker.get({ source = "explorer" })[1]
				if not p or p.closed then
					return
				end
				require("snacks.explorer.git").refresh(p:cwd())
				require("snacks.explorer.actions").update(p, { refresh = true })
			end

			-- `nvim <file>`: open the tree unfocused (dirs are replace_netrw's)
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

			-- 40 cols while any explorer window (input/list/preview, so `/` doesn't shrink it) is
			-- focused, else 24. Resize the root split: the list float just follows it.
			vim.api.nvim_create_autocmd("WinEnter", {
				group = grp,
				callback = function()
					local p = Snacks.picker and Snacks.picker.get({ source = "explorer" })[1]
					if not (p and p.list and p.list.win and p.list.win:valid()) then
						return
					end
					local root = p.layout and p.layout.root and p.layout.root.win
					if not (root and vim.api.nvim_win_is_valid(root)) then
						return
					end
					local cur = vim.api.nvim_get_current_win()
					local in_explorer = false
					for _, w in ipairs({ p.input, p.list, p.preview }) do
						if w and w.win and w.win:valid() and w.win.win == cur then
							in_explorer = true
							break
						end
					end
					vim.api.nvim_win_set_width(root, in_explorer and 40 or 24)
				end,
			})

			-- e.g. after a commit in another tmux pane (needs tmux focus-events)
			vim.api.nvim_create_autocmd("FocusGained", {
				group = grp,
				callback = refresh_git,
			})

			-- `:q` on the last file window: close the explorer too so nvim exits instead of
			-- parking on the sidebar. Close windows directly: picker:close() defers via
			-- vim.schedule, which races the quit.
			vim.api.nvim_create_autocmd("QuitPre", {
				group = grp,
				callback = function()
					local p = Snacks.picker and Snacks.picker.get({ source = "explorer" })[1]
					if not p or p.closed then
						return
					end
					-- explorer windows: root split + floats
					local ex = {}
					local root = p.layout and p.layout.root and p.layout.root.win
					if root and vim.api.nvim_win_is_valid(root) then
						ex[root] = true
					end
					for _, w in ipairs({ p.input, p.list, p.preview }) do
						if w and w.win and w.win:valid() then
							ex[w.win.win] = true
						end
					end
					-- quitting from the sidebar itself: snacks' business
					if ex[vim.api.nvim_get_current_win()] then
						return
					end
					-- non-float, non-explorer windows; the one being quit still counts
					local real = 0
					for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
						if vim.api.nvim_win_get_config(win).relative == "" and not ex[win] then
							real = real + 1
						end
					end
					if real <= 1 then
						for win in pairs(ex) do
							pcall(vim.api.nvim_win_close, win, true)
						end
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
							-- `w` title flag while wrap is on (`W` below), like the h/i flags
							toggles = { wrap = "w" },
							layout = { layout = { width = 24, min_width = 24 } },
							-- files open tmux-style (tabs.open); dirs / search hits use stock confirm.
							-- Own name: the explorer force-overrides a user `confirm`.
							actions = {
								tab_open = function(picker, item, action)
									if item and not item.dir and not picker.input.filter.meta.searching then
										require("config.tabs").open(Snacks.picker.util.path(item))
									else
										require("snacks.explorer.actions").actions.confirm(picker, item, action)
									end
								end,
							},
							win = {
								-- <Esc> in the `/` search box returns to the tree instead of closing
								input = {
									keys = {
										["<Esc>"] = { "toggle_focus", mode = { "i", "n" } },
									},
								},
								list = {
									keys = {
										-- <Esc> doesn't close the tree (`q` does)
										["<Esc>"] = false,
										["i"] = "tab_open", -- Colemak right: open file / expand dir
										["l"] = "tab_open",
										["<CR>"] = "tab_open",
										["<2-LeftMouse>"] = "tab_open",
										["m"] = "explorer_close", -- Colemak left: collapse dir
										["R"] = refresh_git,
										-- move marked files here (else rename); `m` is collapse
										["M"] = "explorer_move",
										-- copy ~-paths of the item / marked items to the clipboard (stock
										-- explorer_yank uses the unnamed register on a bare `y`)
										["y"] = function()
											local p = Snacks.picker.get({ source = "explorer" })[1]
											if not p then
												return
											end
											local files = {}
											for _, item in ipairs(p:selected({ fallback = true })) do
												files[#files + 1] = vim.fn.fnamemodify(Snacks.picker.util.path(item), ":~")
											end
											p.list:set_selected() -- clear marks, matching explorer_yank
											vim.fn.setreg("+", table.concat(files, "\n"), "l")
											Snacks.notify.info("Yanked " .. #files .. " path(s) to clipboard")
										end,
										-- open + browser preview (config/preview.lua); dirs skipped
										["o"] = function()
											local p = Snacks.picker.get({ source = "explorer" })[1]
											if not p then
												return
											end
											local item = p:current()
											if not item or item.dir then
												return
											end
											p:action("tab_open") -- open in its tab, not the sidebar
											require("config.preview").current()
										end,
										-- toggle wrap; opts.wrap + update_titles drive the `w` flag
										["W"] = function(self)
											local wrap = not vim.wo[self.win].wrap
											vim.wo[self.win].wrap = wrap
											local p = Snacks.picker.get({ source = "explorer" })[1]
											if p then
												p.opts.wrap = wrap
												p:update_titles()
											end
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
				"<leader>o",
				function()
					-- in the tree: back to the previous window; else reveal the file and focus
					-- the tree (reveal() doesn't focus an already-open one)
					local p = Snacks.picker.get({ source = "explorer" })[1]
					if p and p:is_focused() then
						vim.cmd("wincmd p")
					else
						Snacks.explorer.reveal()
						p = Snacks.picker.get({ source = "explorer" })[1]
						if p then
							-- the list: a tree opened with focus = false would focus the input
							p:focus("list")
						end
					end
				end,
				desc = "focus / leave file tree",
			},
		},
	},

	-- yazi.nvim: yazi as a file picker. `cond` (not `enabled`) keeps it in lazy-lock.json
	-- where yazi is missing.
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
			-- `:edit <dir>` would toggle the explorer (replace_netrw); the hook cds instead
			open_file_function = function(chosen)
				if vim.fn.isdirectory(chosen) == 0 then
					require("yazi.openers").open_file(chosen)
				end
			end,
			hooks = {
				-- cd to the picked dir, else yazi's last dir (the tree follows DirChanged).
				-- Exactly one cd: two in a row can list the dir twice in the tree (snacks race).
				yazi_closed_successfully = function(chosen, _, state)
					if chosen and vim.fn.isdirectory(chosen) == 1 then
						vim.cmd.cd(chosen)
					else
						vim.cmd.cd(state.last_directory.filename)
					end
				end,
			},
		},
	},

	-- live-preview.nvim: browser preview of html/svg/…, reloads on save. Pure Lua, so
	-- it works on every host.
	{
		"brianhuster/live-preview.nvim",
		cmd = "LivePreview",
		config = function()
			require("livepreview.config").set()
		end,
	},
}
