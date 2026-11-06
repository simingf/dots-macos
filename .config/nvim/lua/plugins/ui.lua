-- standalone PNGs with a longer side (px) are downscaled by magick (snacks image)
local PNG_MAX = 4096

local tabs = require("config.tabs")

return {

	-- which-key
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			spec = {
				{ "<leader>v", proxy = "<c-w>", group = "windows" },
				{ "<leader>d", group = "trouble" },
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

	-- theme: rose-pine with the shared brighter iris
	{
		"rose-pine/neovim",
		name = "rose-pine",
		config = function()
			require("rose-pine").setup({
				palette = {
					-- shared with tmux / ghostty / lazygit
					main = { iris = "#ceacf6" },
					moon = { iris = "#ceacf6" },
				},
				highlight_groups = {
					WinSeparator = { fg = "iris" },
					FloatBorder = { fg = "iris" },
					CursorLineNr = { fg = "iris", bold = true },
					PmenuSel = { fg = "base", bg = "iris" },
					Visual = { bg = "iris", blend = 25 },
				},
			})
			vim.cmd("colorscheme rose-pine")
			-- pickers + explorer on the editor bg (not NormalFloat's lighter surface).
			-- Re-applied on ColorScheme, which clears custom groups.
			local function style_picker()
				for _, g in ipairs({ "SnacksPicker", "SnacksPickerList", "SnacksPickerInput", "SnacksPickerBox" }) do
					vim.api.nvim_set_hl(0, g, { link = "Normal" })
				end
				-- entry colors mirror $LS_COLORS: dir iris, symlink foam, broken link love
				-- (snacks colors by category, not extension; the devicon carries type)
				vim.api.nvim_set_hl(0, "SnacksPickerDirectory", { fg = "#ceacf6", bold = true })
				vim.api.nvim_set_hl(0, "SnacksPickerLink", { fg = "#9ccfd8" })
				vim.api.nvim_set_hl(0, "SnacksPickerLinkBroken", { fg = "#eb6f92" })
			end
			vim.api.nvim_create_autocmd("ColorScheme", { callback = style_picker })
			style_picker()
		end,
	},

	-- lualine: status line
	{
		"nvim-lualine/lualine.nvim",
		-- deps: components used below (recorder slots, diagnostic-message)
		dependencies = { "chrisgrieser/nvim-recorder", "Isrothy/lualine-diagnostic-message" },
		config = function()
			local recorder = require("recorder")
			-- rose-pine theme with iris normal mode
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
					theme = rose_pine_iris,
					component_separators = "|",
					section_separators = "",
					disabled_filetypes = { statusline = { "snacks_picker_list" } },
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
							line_separator = ". ", -- joins multi-line messages
							first_line_only = false,
						},
					},
					lualine_x = { "encoding", "fileformat", "filetype" },
					lualine_y = { "progress", { recorder.displaySlots } },
					lualine_z = { "location", { recorder.recordingStatus } },
				},
			})
		end,
	},

	-- bufferline: tabpages as clickable tabs, like tmux windows. Keys mirror tmux:
	-- <leader>,/. prev/next, </> move, 1-9 jump, <Tab>/W last, c new, k close, bp pick
	{
		"akinsho/bufferline.nvim",
		version = "*",
		event = "VeryLazy",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			options = {
				mode = "tabs", -- tabpages, not buffers
				-- name after the tab's file window (not the focused explorer → "[No Name]");
				-- an empty split defers to the tab's first named file
				name_formatter = function(t)
					if not (t.tabnr and vim.api.nvim_tabpage_is_valid(t.tabnr)) then
						return
					end
					local wins = vim.api.nvim_tabpage_list_wins(t.tabnr)
					local fw = tabs.file_win(t.tabnr)
					if fw then
						table.insert(wins, 1, fw)
					end
					for _, w in ipairs(wins) do
						local buf = vim.api.nvim_win_get_buf(w)
						local name = vim.api.nvim_buf_get_name(buf)
						if vim.bo[buf].buftype == "" and name ~= "" then
							return vim.fn.fnamemodify(name, ":t")
						end
					end
				end,
				diagnostics = "nvim_lsp",
				-- flat bg: the current tab is marked by an iris underline
				indicator = { style = "underline" },
				-- no tabline-wide ✕ (closes an unnamed tab); per-tab ✕ stay
				show_close_icon = false,
				close_command = tabs.close,
				right_mouse_command = tabs.close,
				offsets = {
					{
						filetype = "snacks_picker_list",
						text = "File Explorer",
						highlight = "Directory",
						separator = true,
					},
				},
			},
			-- selected tab in iris, like tmux's window tabs
			highlights = {
				fill = { bg = "#191724" },
				buffer_selected = { fg = "#ceacf6", bg = "#191724", bold = true, italic = false, underline = true, sp = "#ceacf6" },
				numbers_selected = { fg = "#ceacf6", bg = "#191724" },
				indicator_selected = { fg = "#ceacf6", bg = "#191724" },
			},
		},
		config = function(_, opts)
			-- flatten bufferline's darker inactive-tab bgs to the editor bg, via opts so
			-- bufferline applies them itself (no race)
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
			-- unsaved tabs: show ● as the icon and keep the ✕ (bufferline would swap ✕ → ●,
			-- making it unclosable). Wraps the internal Tabpage model (FRAGILE.md).
			local Tabpage = require("bufferline.models").Tabpage
			local tab_new = Tabpage.new
			Tabpage.new = function(self, tab)
				local t = tab_new(self, tab)
				if t.modified then
					t.modified = false
					t.icon, t.icon_highlight = "●", "BufferLineModifiedSelected"
				end
				return t
			end
			require("bufferline").setup(opts)
		end,
		keys = vim.list_extend({
			{ "<leader>,", "<cmd>tabprevious<cr>", desc = "prev tab" },
			{ "<leader>.", "<cmd>tabnext<cr>", desc = "next tab" },
			{ "<leader><", "<cmd>silent! tabmove -1<cr>", desc = "move tab left" },
			{ "<leader>>", "<cmd>silent! tabmove +1<cr>", desc = "move tab right" },
			{ "<leader><Tab>", "<cmd>tabnext #<cr>", desc = "last tab" },
			{ "<leader>W", "<cmd>tabnext #<cr>", desc = "last tab" },
			{ "<leader>c", tabs.new, desc = "new tab" },
			{ "<leader>k", function() tabs.close() end, desc = "close tab" },
			{ "<leader>bp", "<cmd>BufferLinePick<cr>", desc = "pick tab" },
			{ "<leader>!", function() tabs.break_out() end, desc = "split → own tab" },
		}, vim.tbl_map(function(n)
			-- like tmux ‹pfx›1-9: a missing tab toasts instead of erroring
			return {
				"<leader>" .. n,
				function()
					if not pcall(vim.cmd, n .. "tabnext") then
						vim.notify("no tab " .. n)
					end
				end,
				desc = "tab " .. n,
			}
		end, { 1, 2, 3, 4, 5, 6, 7, 8, 9 })),
	},

	-- snacks.nvim: picker, notifier, image, indent, bigfile, quickfile (+ explorer: navigation.lua)
	{
		"folke/snacks.nvim",
		priority = 1000, -- load early so vim.notify is snacks.notifier asap
		lazy = false,
		init = function()
			-- snacks.image can't detect ghostty through tmux (TERM is xterm-256color, and
			-- XTVERSION can't come back through passthrough), so flag it. A pane's env is
			-- snapshotted at spawn and can go stale, so fall back to tmux's global env.
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
			picker = {
				ui_select = true, -- also replaces vim.ui.select
				-- file pickers open tmux-style (tabs.jump); <C-v>/<C-s>/<C-t> and multi-select
				-- keep snacks' own jump
				actions = {
					tab_jump = function(picker, item, action)
						local items = picker:selected({ fallback = true })
						local path = item and (item.buf and vim.api.nvim_buf_get_name(item.buf) or Snacks.picker.util.path(item))
						if action.cmd or #items > 1 or not path or path == "" then
							return Snacks.picker.actions.jump(picker, item, action)
						end
						-- buffer items' pos is the last-left mark: don't move a split already showing it
						local pos = item.pos
						if picker.opts.source == "buffers" and #vim.fn.win_findbuf(item.buf) > 0 then
							pos = nil
						end
						picker:close()
						vim.cmd.stopinsert()
						vim.schedule(function()
							tabs.jump(path, pos)
						end)
					end,
				},
				sources = vim.tbl_map(function()
					return { confirm = "tab_jump" }
				end, { files = 0, recent = 0, grep = 0, grep_buffers = 0, buffers = 0, diagnostics = 0 }),
			},
			notifier = { enabled = true },
			bigfile = { enabled = true },
			quickfile = { enabled = true },
			image = { -- inline image preview (kitty graphics; needs chafa/imagemagick)
				enabled = true,
				convert = { magick = { png = { "{src}[0]", "-scale", PNG_MAX .. "x" .. PNG_MAX .. ">" } } },
			},
			-- indent guides + current scope
			indent = { indent = { char = "▏" }, scope = { char = "▏" } },
		},
		config = function(_, opts)
			require("snacks").setup(opts)
			-- Standalone image buffers: patches snacks internals (FRAGILE.md, healthcheck.lua).
			-- • hide() on leave is never undone for non-inline images: un-hide once back in a
			--   window (patched before any placement exists; new() captures update)
			-- • without magick (dev box) identify fails and error() writes "Image Conversion
			--   Failed" over an image that displays fine: skip it when the image is ready
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
			-- • fit() only shrinks: scale to the largest aspect-kept size the window holds
			--   (WinResized re-runs update())
			local state = P.state
			function P:state()
				local s = state(self)
				if self.opts.inline or #s.wins == 0 then
					return s
				end
				local ok, px = pcall(function()
					return self.img.info and self.img.info.size or Snacks.image.util.dim(self.img.file)
				end)
				if not ok or not px or px.width == 0 or px.height == 0 then
					return s
				end
				local w, h = math.huge, math.huge
				for _, win in ipairs(s.wins) do
					w = math.min(w, vim.api.nvim_win_get_width(win))
					h = math.min(h, vim.api.nvim_win_get_height(win))
				end
				local term = Snacks.image.terminal.size()
				local iw, ih = px.width / term.cell_width, px.height / term.cell_height
				local scale = math.min(w / iw, h / ih)
				s.loc.width = math.max(1, math.floor(iw * scale))
				s.loc.height = math.max(1, math.floor(ih * scale))
				return s
			end
			-- • progress()/error() leave image buffers 'modified' (save prompt on close, E37
			--   on :edit); they're read-only, so keep them unmodified
			vim.api.nvim_create_autocmd("BufModifiedSet", {
				group = vim.api.nvim_create_augroup("snacks_image_unmodified", { clear = true }),
				callback = function(ev)
					if vim.bo[ev.buf].filetype == "image" and vim.bo[ev.buf].modified then
						vim.bo[ev.buf].modified = false
					end
				end,
			})
			-- • snacks caches images per path (session + disk) ignoring mtime, so an image
			--   overwritten in place shows stale pixels; the patches below check mtime
			local uv = vim.uv
			local function mtime(f)
				local st = uv.fs_stat(f)
				return st and st.mtime.sec + st.mtime.nsec / 1e9
			end
			local C = require("snacks.image.convert")
			local convert = C.convert
			-- • PNGs skip magick and go out full size (terminals drop >10000px, slow over ssh):
			--   send ones over PNG_MAX through the convert step (opts' magick.png scales them)
			local Convert
			for i = 1, 50 do
				local n, v = debug.getupvalue(convert, i)
				if n == "Convert" or not n then
					Convert = v
					break
				end
			end
			if Convert then
				local resolve = Convert.resolve
				function Convert:resolve()
					local ok, px = pcall(Snacks.image.util.dim, self.src)
					if self:ft() == "png" and not C.is_uri(self.src) and vim.fn.executable("magick") == 1
						and ok and math.max(px.width, px.height) > PNG_MAX then
						self:_resolve("convert")
					end
					return resolve(self)
				end
			end
			-- disk cache: drop step outputs older than the source, then re-resolve
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
			-- session cache: rebuild the Image when its source changed
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
			-- open image buffers get no checktime (BufReadCmd): re-attach when the file changed
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
			-- tmux ‹pfx›w (fzf window switch) / ‹pfx›f (grep scrollback across panes)
			{
				"<leader>w",
				function()
					Snacks.picker.buffers()
				end,
				desc = "switch buffer",
			},
			{
				"<leader>f",
				function()
					Snacks.picker.grep_buffers()
				end,
				desc = "grep open buffers",
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
		},
	},

	-- highlight other occurrences of the word under the cursor
	{
		"echasnovski/mini.cursorword",
		event = "VeryLazy",
		config = true,
	},
}
