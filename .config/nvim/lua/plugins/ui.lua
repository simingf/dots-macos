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
			-- snacks pickers (incl. the explorer sidebar) default their window bg to
			-- NormalFloat — rose-pine's lighter "surface" (#1f1d2e) — so the sidebar
			-- reads as a paler purple than the editor. Link the base picker groups to
			-- Normal (#191724) so they match. Also applies to the floating pickers.
			-- Re-run on every ColorScheme since rose-pine clears custom groups on load.
			local function style_picker()
				for _, g in ipairs({ "SnacksPicker", "SnacksPickerList", "SnacksPickerInput", "SnacksPickerBox" }) do
					vim.api.nvim_set_hl(0, g, { link = "Normal" })
				end
				-- Explorer/picker entry colors mirror $LS_COLORS (zsh `ls` is the source
				-- of truth): directory = iris, symlink = foam, broken link = love.
				-- Regular files stay default text; per-extension type color rides on the
				-- devicon, since snacks paints filenames by category, not extension.
				vim.api.nvim_set_hl(0, "SnacksPickerDirectory", { fg = "#ceacf6", bold = true })
				vim.api.nvim_set_hl(0, "SnacksPickerLink", { fg = "#9ccfd8" })
				vim.api.nvim_set_hl(0, "SnacksPickerLinkBroken", { fg = "#eb6f92" })
			end
			vim.api.nvim_create_autocmd("ColorScheme", { callback = style_picker })
			style_picker()
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
						statusline = { "snacks_picker_list" },
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
	-- select tabs (mouse = "a"); <leader>bi/bm cycle next/prev and <leader>bp jumps by letter.
	-- offsets shifts the bar right of the explorer sidebar so they don't overlap;
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
				-- all tab backgrounds are uniform, so the current buffer is marked
				-- by a full-width bright-iris underline rather than a bg shift.
				indicator = { style = "underline" },
				-- close via Snacks so the window layout survives: the default
				-- `bdelete %d` collapses the edit window when the last buffer
				-- goes, letting the explorer sidebar expand to fill the screen.
				close_command = function(n)
					Snacks.bufdelete(n)
				end,
				right_mouse_command = function(n)
					Snacks.bufdelete(n)
				end,
				offsets = {
					{
						filetype = "snacks_picker_list",
						text = "File Explorer",
						highlight = "Directory",
						separator = true,
					},
				},
			},
			-- iris-forward: selected buffer tab picks up the shared iris (matches tmux window tabs)
			highlights = {
				-- fill, unselected, visible, and selected tabs all share the editor bg
				-- so the tabline reads as one flat surface; the current buffer stands
				-- out via a bright-iris underline (see indicator) instead of a bg shift.
				fill = { bg = "#191724" },
				buffer_selected = { fg = "#ceacf6", bg = "#191724", bold = true, italic = false, underline = true, sp = "#ceacf6" },
				numbers_selected = { fg = "#ceacf6", bg = "#191724" },
				indicator_selected = { fg = "#ceacf6", bg = "#191724" },
			},
		},
		config = function(_, opts)
			-- bufferline darkens inactive-tab backgrounds by default (#12111b for
			-- unselected, #171521 for visible), which made unselected tabs read as a
			-- separate shade. Override bg to the editor bg on every unselected/visible
			-- element so the whole tabline is one flat surface — the current buffer is
			-- marked by its bright-iris underline (indicator) instead of a bg shift.
			-- Done through highlights opts so bufferline applies it itself (no race).
			opts.highlights = opts.highlights or {}
			for _, k in ipairs({
				"background", "buffer_visible",
				"close_button", "close_button_visible",
				"modified", "modified_visible",
				"duplicate", "duplicate_visible",
				"numbers", "numbers_visible",
				"separator", "separator_visible",
				"pick", "pick_visible",
				"indicator_visible",
				"diagnostic", "diagnostic_visible",
				"hint", "hint_visible", "hint_diagnostic", "hint_diagnostic_visible",
				"info", "info_visible", "info_diagnostic", "info_diagnostic_visible",
				"warning", "warning_visible", "warning_diagnostic", "warning_diagnostic_visible",
				"error", "error_visible", "error_diagnostic", "error_diagnostic_visible",
			}) do
				opts.highlights[k] = vim.tbl_extend("force", opts.highlights[k] or {}, { bg = "#191724" })
			end
			require("bufferline").setup(opts)
		end,
		keys = {
			{ "<leader>bi", "<cmd>BufferLineCycleNext<cr>", desc = "next buffer" },
			{ "<leader>bm", "<cmd>BufferLineCyclePrev<cr>", desc = "prev buffer" },
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
			-- explicitly under ghostty. GHOSTTY_RESOURCES_DIR is set by ghostty (and
			-- TERM_PROGRAM=="ghostty" outside tmux; inside tmux it's overwritten to
			-- "tmux"). Both are snapshotted into a pane's env at spawn, so a pane that
			-- outlived a ghostty update (persistent tmux server) loses them and images
			-- silently break — fall back to tmux's live global env. (Skipped over SSH,
			-- so linux/windows no-op.)
			local function is_ghostty()
				if vim.env.GHOSTTY_RESOURCES_DIR or vim.env.TERM_PROGRAM == "ghostty" then
					return true
				end
				if vim.env.TMUX and not require("config.env").IS_SSH then
					local v = vim.fn.system({ "tmux", "show-environment", "-g", "GHOSTTY_RESOURCES_DIR" })
					return vim.v.shell_error == 0 and v:match("^GHOSTTY_RESOURCES_DIR=%S") ~= nil
				end
				return false
			end
			if is_ghostty() then
				vim.env.SNACKS_GHOSTTY = "1"
			end
		end,
		opts = {
			picker = { ui_select = true }, -- also replaces vim.ui.select
			notifier = { enabled = true },
			bigfile = { enabled = true },
			quickfile = { enabled = true },
			image = { enabled = true }, -- inline image preview (kitty graphics; needs chafa/imagemagick)
			-- indent guides + current-scope highlight (replaced indent-blankline)
			indent = { indent = { char = "▏" }, scope = { char = "▏" } },
		},
		config = function(_, opts)
			require("snacks").setup(opts)
			-- Standalone image buffers (patches snacks internals — see config.healthcheck):
			-- • leaving the window calls placement:hide(), but only inline/doc images ever
			--   call show(), so the image stays blank on return. Un-hide when it's back
			--   in a window. (Patched before any placement exists; new() captures update.)
			-- • without magick (dev box) the `identify` metadata step fails and error()
			--   writes "Image Conversion Failed" into the buffer — even though the PNG
			--   itself was already sent and displays. Skip it when the image is ready.
			local P = require("snacks.image.placement")
			local update, err = P.update, P.error
			function P:update()
				if self.hidden and not self.opts.inline and #self:wins() > 0 then
					self.hidden = false
				end
				return update(self)
			end
			function P:error()
				if not self.img:ready() then
					return err(self)
				end
			end
			-- snacks' progress()/error() set_lines after attach resets 'modified', so an
			-- image buffer comes up modified: closing prompts to save, and `:edit`
			-- fails with E37. Image buffers are read-only.
			vim.api.nvim_create_autocmd("BufModifiedSet", {
				group = vim.api.nvim_create_augroup("snacks_image_unmodified", { clear = true }),
				callback = function(ev)
					if vim.bo[ev.buf].filetype == "image" and vim.bo[ev.buf].modified then
						vim.bo[ev.buf].modified = false
					end
				end,
			})
			-- Overwriting an image in place (e.g. /render-diagram) showed the old pixels until
			-- nvim restarted: snacks caches images per path both in-session (already-sent
			-- Image objects) and on disk (identify info, svg→png), never checking mtime.
			local uv = vim.uv
			local function mtime(f)
				local st = uv.fs_stat(f)
				return st and st.mtime.sec + st.mtime.nsec / 1e9
			end
			-- • disk: drop cached step outputs older than the source, then re-resolve
			local C = require("snacks.image.convert")
			local convert = C.convert
			function C.convert(opts)
				local c = convert(vim.tbl_extend("force", {}, opts)) -- new() mutates opts.src
				local src, stale = mtime(c.src), false
				for _, step in ipairs(c.steps) do
					local m = step.done and mtime(step.file)
					if src and m and m < src then
						os.remove(step.file)
						stale = true
					end
				end
				return stale and convert(opts) or c
			end
			-- • session: rebuild the Image when its source changed since it was created
			local I = require("snacks.image.image")
			local new = I.new
			function I.new(src)
				local img = new(src)
				local m = mtime(img.src)
				if img._mtime and img._mtime ~= m then
					I.clear() -- the cache table is local; this only forces re-sends
					img = new(src)
				end
				img._mtime = img._mtime or m
				return img
			end
			-- • an already-open image buffer isn't re-read on switch (no checktime for
			--   BufReadCmd buffers), so re-attach it when its file changed
			vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
				group = vim.api.nvim_create_augroup("snacks_image_reload", { clear = true }),
				callback = function()
					local buf = vim.api.nvim_get_current_buf()
					if vim.bo[buf].filetype ~= "image" then
						return
					end
					local m = mtime(vim.api.nvim_buf_get_name(buf))
					if vim.b[buf].image_mtime and vim.b[buf].image_mtime ~= m then
						Snacks.image.buf.attach(buf)
					end
					vim.b[buf].image_mtime = m
				end,
			})
		end,
		keys = {
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

	-- highlight all occurences of a word
	{
		"echasnovski/mini.cursorword",
		event = "VeryLazy",
		config = true,
	},
}
