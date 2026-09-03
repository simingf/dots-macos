return {

	-- which key
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			spec = {
				{ "<leader>w", proxy = "<c-w>", group = "windows" },
				{ "<leader>x", group = "trouble" },
				{ "<leader>t", group = "pickers" },
				{ "<leader>b", group = "buffer" },
			},
		},
		keys = {
			{
				"<leader><leader>",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Local Keymaps (which-key)",
			},
		},
	},

	-- theme
	{
		"rose-pine/neovim",
		name = "rose-pine",
		config = function()
			require("rose-pine").setup({
				palette = {
					-- custom brighter iris — shared #ceacf6 across tmux / ghostty / lazygit
					main = { iris = "#ceacf6" },
					moon = { iris = "#ceacf6" },
				},
				highlight_groups = {
					-- iris-forward: structural accents pick up the shared iris
					WinSeparator = { fg = "iris" },
					FloatBorder = { fg = "iris" },
					CursorLineNr = { fg = "iris", bold = true },
					PmenuSel = { fg = "base", bg = "iris" },
					Visual = { bg = "iris", blend = 25 },
				},
			})
			vim.cmd("colorscheme rose-pine")
		end,
	},

	-- status line at bottom
	{
		"nvim-lualine/lualine.nvim",
		-- lualine_c uses the "diagnostic-message" component from lualine-diagnostic-message;
		-- declare it a dependency so it's on the rtp before lualine configures (no load-order luck).
		dependencies = { "chrisgrieser/nvim-recorder", "Isrothy/lualine-diagnostic-message" },
		config = function()
			local recorder = require("recorder")
			-- iris-forward rose-pine lualine theme — normal mode = iris (#ceacf6), shared palette
			local p = {
				base = "#191724", surface = "#1f1d2e", overlay = "#26233a",
				muted = "#6e6a86", subtle = "#908caa", text = "#e0def4",
				love = "#eb6f92", gold = "#f6c177", rose = "#ebbcba",
				pine = "#31748f", foam = "#9ccfd8", iris = "#ceacf6",
			}
			local rose_pine_iris = {
				normal = {
					a = { fg = p.base, bg = p.iris, gui = "bold" },
					b = { fg = p.text, bg = p.overlay },
					c = { fg = p.subtle, bg = p.surface },
				},
				insert = { a = { fg = p.base, bg = p.foam, gui = "bold" } },
				visual = { a = { fg = p.base, bg = p.rose, gui = "bold" } },
				replace = { a = { fg = p.base, bg = p.love, gui = "bold" } },
				command = { a = { fg = p.base, bg = p.gold, gui = "bold" } },
				inactive = {
					a = { fg = p.muted, bg = p.surface },
					b = { fg = p.muted, bg = p.surface },
					c = { fg = p.muted, bg = p.surface },
				},
			}
			require("lualine").setup({
				options = {
					icons_enabled = true,
					theme = rose_pine_iris,
					-- component_separators = { left = '', right = '' },
					component_separators = "|",
					-- section_separators = { left = '', right = '' },
					section_separators = "",
					disabled_filetypes = {
						statusline = { "neo-tree" },
						winbar = {},
					},
					ignore_focus = {},
					always_divide_middle = true,
					always_show_tabline = true,
					globalstatus = false,
					refresh = {
						statusline = 100,
						tabline = 100,
						winbar = 100,
					},
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = {
						{ "filename", path = 1 },
						{
							"diagnostic-message",
							icons = {
								error = "",
								warn = "",
								info = "",
								hint = "",
							},
							-- Replace '\n' by the separator
							line_separator = ". ",
							-- Only show the first line of diagnostic message
							first_line_only = false,
						},
					},
					lualine_x = { "encoding", "fileformat", "filetype" },
					lualine_y = { "progress", { recorder.displaySlots } },
					lualine_z = { "location", { recorder.recordingStatus } },
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { "filename" },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				tabline = {},
				winbar = {},
				inactive_winbar = {},
				extensions = {},
			})
		end,
	},

	-- bufferline: open buffers as clickable tabs across the top. Mouse clicks
	-- select tabs (mouse = "a"); [b / ]b cycle and <leader>bp jumps by letter.
	-- offsets shifts the bar right of the neo-tree sidebar so they don't overlap;
	-- rose-pine themes the highlights automatically.
	{
		"akinsho/bufferline.nvim",
		version = "*",
		event = "VeryLazy",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			options = {
				mode = "buffers", -- every buffer is a tab (not vim tabpages)
				diagnostics = "nvim_lsp",
				-- close via Snacks so the window layout survives: the default
				-- `bdelete %d` collapses the edit window when the last buffer
				-- goes, letting neo-tree expand to fill the screen.
				close_command = function(n)
					Snacks.bufdelete(n)
				end,
				right_mouse_command = function(n)
					Snacks.bufdelete(n)
				end,
				offsets = {
					{
						filetype = "neo-tree",
						text = "File Explorer",
						highlight = "Directory",
						separator = true,
					},
				},
			},
			-- iris-forward: selected buffer tab picks up the shared iris (matches tmux window tabs)
			highlights = {
				buffer_selected = { fg = "#ceacf6", bold = true, italic = false },
				numbers_selected = { fg = "#ceacf6" },
				indicator_selected = { fg = "#ceacf6" },
			},
		},
		keys = {
			{ "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "prev buffer" },
			{ "]b", "<cmd>BufferLineCycleNext<cr>", desc = "next buffer" },
			{ "<leader>bp", "<cmd>BufferLinePick<cr>", desc = "pick buffer" },
		},
	},

	-- snacks.nvim: picker, notifier, bigfile, quickfile (replaces telescope + nvim-notify)
	{
		"folke/snacks.nvim",
		priority = 1000, -- load early so vim.notify is snacks.notifier asap
		lazy = false,
		init = function()
			-- snacks.image can't auto-detect ghostty inside tmux: tmux reports our
			-- overridden `xterm-256color` (ghostty config) as client_termname, and the
			-- XTVERSION reply can't return through tmux's one-way passthrough. Flag it
			-- explicitly under ghostty. Key off GHOSTTY_RESOURCES_DIR — it's set by
			-- ghostty and survives into the tmux session env, whereas TERM_PROGRAM gets
			-- overwritten to "tmux" inside tmux. (Unset over SSH, so linux/windows no-op.)
			if vim.env.GHOSTTY_RESOURCES_DIR or vim.env.TERM_PROGRAM == "ghostty" then
				vim.env.SNACKS_GHOSTTY = "1"
			end
			-- Switching buffers (bufferline) away from and back to an image drops the
			-- kitty image — snacks deletes it on hide, then only re-places (by id) on
			-- return, but the data is gone, so nothing shows. Reloading the buffer on
			-- entry (what <leader>ri does) forces a fresh transmit. The `reloading` flag
			-- stops the :edit from re-triggering this handler. ghostty only.
			if vim.env.GHOSTTY_RESOURCES_DIR or vim.env.TERM_PROGRAM == "ghostty" then
				local reloading = false
				vim.api.nvim_create_autocmd("BufEnter", {
					group = vim.api.nvim_create_augroup("snacks_image_rerender", { clear = true }),
					callback = function(ev)
						if reloading or vim.bo[ev.buf].filetype ~= "image" then
							return
						end
						reloading = true
						vim.schedule(function()
							if vim.bo.filetype == "image" then
								pcall(vim.cmd, "edit")
							end
							reloading = false
						end)
					end,
				})
			end
		end,
		opts = {
			picker = { ui_select = true }, -- also replaces vim.ui.select
			notifier = { enabled = true },
			bigfile = { enabled = true },
			quickfile = { enabled = true },
			image = { enabled = true }, -- inline image preview (kitty graphics; needs chafa/imagemagick)
		},
		keys = {
			{
				"<leader>ri",
				function()
					-- Re-render a standalone image that nvim dropped on a tabpage redraw.
					-- Reloading the buffer re-runs snacks' image attach → fresh transmit.
					-- (<leader>i is taken by window-nav, so this lives under <leader>r.)
					if vim.bo.filetype == "image" then
						vim.cmd("edit")
					else
						vim.notify("Not an image buffer", vim.log.levels.WARN)
					end
				end,
				desc = "re-render image",
			},
			{
				"<leader>tt",
				function()
					Snacks.picker.lines()
				end,
				desc = "fuzzy find in buffer",
			},
			{
				"<leader>tg",
				function()
					Snacks.picker.grep()
				end,
				desc = "live grep",
			},
			{
				"<leader>tb",
				function()
					Snacks.picker.buffers()
				end,
				desc = "buffers",
			},
			{
				"<leader>tf",
				function()
					Snacks.picker.files()
				end,
				desc = "find files",
			},
			{
				"<leader>tr",
				function()
					Snacks.picker.recent()
				end,
				desc = "recent files",
			},
			{
				"<leader>td",
				function()
					Snacks.picker.diagnostics()
				end,
				desc = "diagnostics",
			},
			{
				"<leader>tn",
				function()
					Snacks.picker.notifications()
				end,
				desc = "notifications",
			},
			{
				"<leader>bc",
				function()
					Snacks.bufdelete()
				end,
				desc = "close buffer",
			},
		},
	},

	-- indentation indicators on the left
	{
		"lukas-reineke/indent-blankline.nvim",
		event = "VeryLazy",
		main = "ibl", -- setup module is `ibl`, not the plugin name
		-- enabled + scope.enabled are ibl v3 defaults; only the char is an override.
		opts = { indent = { char = "▏" } },
	},

	-- highlight all occurences of a word
	{
		"echasnovski/mini.cursorword",
		event = "VeryLazy",
		config = true,
	},
}
