-- ========================================================================== --
-- ==                           EDITOR SETTINGS                            == --
-- ========================================================================== --

-- title
vim.opt.title = true
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
	callback = function()
		local title = vim.fn.expand("%:t")
		if title == "" then
			title = "[No Name]"
		end
		vim.opt.titlestring = title
		if vim.env.TMUX then
			io.write("\027k" .. title .. "\027\\")
			io.flush()
		end
	end,
})
-- enable line numbers
vim.opt.number = true
vim.opt.relativenumber = true
-- keep sign column on
vim.opt.signcolumn = "yes"
-- highlight current line
vim.opt.cursorline = true
-- minimal number of screen lines to keep above and below the cursor
vim.opt.scrolloff = 5
-- line wrapping
vim.opt.wrap = true
-- preserve indentation when line wrapping
vim.opt.breakindent = true
-- enable mouse for all modes
vim.opt.mouse = "a"
-- include both lower and upper case for search
vim.opt.ignorecase = true
-- ignore upper case letters unless the search includes upper case letters
vim.opt.smartcase = true
-- disable highlighting the result of the most recent search all the time
vim.opt.hlsearch = false
-- set how many spaces a tab is
vim.opt.tabstop = 4
-- set how many spaces << and >> indent by
vim.opt.shiftwidth = 4
-- enable converting a tab into spaces
vim.opt.expandtab = true
-- disable showing current mode since lualine shows
vim.opt.showmode = false
-- enable hexademical colors instead of only 256 colors
vim.opt.termguicolors = true
-- configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true
-- diagnostic config
local signs_text = {
	[vim.diagnostic.severity.ERROR] = "",
	[vim.diagnostic.severity.WARN] = "",
	[vim.diagnostic.severity.INFO] = "",
	[vim.diagnostic.severity.HINT] = "",
}
vim.diagnostic.config({
	virtual_text = false,
	signs = {
		text = signs_text,
		numhl = {
			[vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
			[vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
			[vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
			[vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
		},
	},
	update_in_insert = false,
	underline = true,
	severity_sort = true,
	float = {
		border = "rounded",
		source = true,
	},
})

-- ========================================================================== --
-- ==                           KEY BINDINGS                               == --
-- ========================================================================== --

-- set the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- (<leader>w → <C-w> chain is registered as a which-key proxy in the plugin spec below
--  so the popup shows the full <C-w>* hint set; ctrl-w is hard to reach otherwise.)
-- Colemak-DH: hjkl ↔ mnei swap. `i` is omitted from operator-pending because it's
-- the text-object prefix (di(, vi", ci{); use `l` for right-movement when needed.
local _nxo = { "n", "x", "o" }
vim.keymap.set(_nxo, "m", "h")
vim.keymap.set(_nxo, "n", "j")
vim.keymap.set(_nxo, "e", "k")
vim.keymap.set({ "n", "x" }, "i", "l")
vim.keymap.set({ "n", "x" }, "j", "n")
vim.keymap.set(_nxo, "k", "e")
vim.keymap.set("n", "l", "i")
-- `h`/`H` are claimed by arrow.nvim (buffer / global UI); use `:mark x` to set marks.
-- pane switching: <leader>{mnei} matches the colemak-swap movement keys
vim.keymap.set("n", "<leader>m", "<C-w>h", { silent = true, desc = "win left" })
vim.keymap.set("n", "<leader>n", "<C-w>j", { silent = true, desc = "win down" })
vim.keymap.set("n", "<leader>e", "<C-w>k", { silent = true, desc = "win up" })
vim.keymap.set("n", "<leader>i", "<C-w>l", { silent = true, desc = "win right" })
-- splits: match tmux (`\` = vertical divider, `-` = horizontal divider)
vim.keymap.set("n", "<leader>\\", "<cmd>vsplit<cr>", { silent = true, desc = "vsplit" })
vim.keymap.set("n", "<leader>-", "<cmd>split<cr>", { silent = true, desc = "hsplit" })
-- prevent x or X from modifying the internal register
vim.keymap.set({ "n", "x" }, "x", '"_x')
vim.keymap.set({ "n", "x" }, "X", '"_d')
-- yank and paste from clipboard
vim.keymap.set({ "n", "x" }, "gy", '"+y', { desc = "yank to clipboard" })
vim.keymap.set("n", "gp", '"+p', { desc = "paste from clipboard" })
-- highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})
-- bind 0 to ^ and L to $ (H is taken by arrow.nvim)
vim.keymap.set({ "n", "x", "o" }, "0", "^", { noremap = true, silent = true })
vim.keymap.set({ "n", "x", "o" }, "L", "$", { noremap = true, silent = true })
-- format with conform (falls back to LSP if no formatter is configured for the filetype)
vim.keymap.set({ "n", "x" }, "<leader>f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "format" })
-- toggle format-on-save: :FormatDisable (buffer) or :FormatDisable! (global), :FormatEnable to re-enable
vim.api.nvim_create_user_command("FormatDisable", function(args)
	if args.bang then
		vim.g.disable_autoformat = true
	else
		vim.b.disable_autoformat = true
	end
end, { desc = "Disable format-on-save", bang = true })
vim.api.nvim_create_user_command("FormatEnable", function()
	vim.b.disable_autoformat = false
	vim.g.disable_autoformat = false
end, { desc = "Re-enable format-on-save" })

-- ========================================================================== --
-- ==                               PLUGINS                                == --
-- ========================================================================== --

if vim.env.NVIM_REMOTE then
	return
end

-- IS_SSH: in an SSH session, skip plugins that need network or ship arch-specific
-- native binaries (Mason, blink.cmp Rust fuzzy). False locally on macOS, so a no-op.
local IS_SSH = (vim.env.SSH_CONNECTION or "") ~= ""

-- HAS_DOTNET: gate the C# / roslyn toolchain. True on the work Mac, false on the
-- personal Windows box. Lets a single init.lua serve all 3 hosts.
local HAS_DOTNET = vim.fn.executable("dotnet") == 1

-- setup code from documentation --
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)
-- setup code from documentation --

require("lazy").setup({
	-- dependencies
	{ "nvim-lua/plenary.nvim" },
	{ "nvim-tree/nvim-web-devicons" },
	{ "tpope/vim-repeat" },

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
			vim.cmd("colorscheme rose-pine")
		end,
	},

	-- status line at bottom
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "chrisgrieser/nvim-recorder" },
		config = function()
			local recorder = require("recorder")
			require("lualine").setup({
				options = {
					icons_enabled = true,
					theme = "auto",
					-- component_separators = { left = '', right = '' },
					component_separators = "|",
					-- section_separators = { left = '', right = '' },
					section_separators = "",
					disabled_filetypes = {
						statusline = {},
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
	{
		"Isrothy/lualine-diagnostic-message",
	},

	-- git indicators on the left
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = true,
	},

	-- indentation indicators on the left
	{
		"lukas-reineke/indent-blankline.nvim",
		event = "VeryLazy",
		config = function()
			require("ibl").setup({
				enabled = true,
				scope = {
					enabled = true,
				},
				indent = {
					char = "▏",
				},
			})
		end,
	},

	-- highlight TODOs
	{
		"folke/todo-comments.nvim",
		event = "VeryLazy",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			keywords = {
				FIX = { icon = " ", color = "error", alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
				TODO = { icon = " ", color = "info", alt = { "NYI" } },
				HINT = { icon = " ", color = "hint", alt = { "INFO", "NOTE" } },
				TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASS", "PASSED", "FAIL", "FAILED" } },
			},
		},
	},

	-- highlight all occurences of a word
	{
		"echasnovski/mini.cursorword",
		event = "VeryLazy",
		config = true,
	},

	-- automatic closing brackets (blink.cmp-aware, LazyVim default)
	{
		"echasnovski/mini.pairs",
		event = "InsertEnter",
		config = true,
	},

	-- flash
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {
			modes = {
				search = {
					enabled = true,
					highlight = { backdrop = false },
				},
			},
		},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
			{
				"S",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "Flash Treesitter",
			},
			{
				"r",
				mode = "o",
				function()
					require("flash").remote()
				end,
				desc = "Remote Flash",
			},
			{
				"R",
				mode = { "o", "x" },
				function()
					require("flash").treesitter_search()
				end,
				desc = "Treesitter Search",
			},
		},
	},

	-- arrow: bookmark files and locations in files
	{
		"otavioschwanck/arrow.nvim",
		dependencies = {
			{ "nvim-tree/nvim-web-devicons" },
		},
		opts = {
			show_icons = true,
			leader_key = "H",
			buffer_leader_key = "h",
		},
	},

	-- recorder: easier macros (uses vim.notify, which snacks.notifier handles)
	{
		"chrisgrieser/nvim-recorder",
		keys = {
			-- these must match the keys in the mapping config below
			{ "q", desc = " Start Recording" },
			{ "Q", desc = " Play Recording" },
			{ "<C-q>", desc = " Switch Recording Slot" },
			{ "cq", desc = " Edit Recording" },
			{ "dq", desc = " Delete All Recordings" },
			{ "yq", desc = " Yank Recording" },
		},
		config = function()
			require("recorder").setup({
				mapping = {
					startStopRecording = "q",
					playMacro = "Q",
					switchSlot = "<C-q>",
					editMacro = "cq",
					deleteAllMacros = "dq",
					yankMacro = "yq",
				},
				-- Clears all macros-slots on startup.
				clear = true,
			})
		end,
	},

	-- trouble: diagnostics windows
	{
		"folke/trouble.nvim",
		opts = {}, -- for default options, refer to the configuration section for custom setup.
		cmd = "Trouble",
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle win.size=0.1<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle win.size=0.1 filter.buf=0<cr>",
				desc = "Buffer Diagnostics (Trouble)",
			},
			{
				"<leader>xs",
				"<cmd>Trouble symbols toggle focus=false win.size=0.25 win.position=right<cr>",
				desc = "Symbols (Trouble)",
			},
			{
				"<leader>xl",
				"<cmd>Trouble lsp toggle focus=false win.size=0.25 win.position=right<cr>",
				desc = "LSP Definitions / references / ... (Trouble)",
			},
			{
				"<leader>xL",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location List (Trouble)",
			},
			{
				"<leader>xQ",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix List (Trouble)",
			},
		},
	},

	-- snacks.nvim: picker, notifier, bigfile, quickfile (replaces telescope + nvim-notify)
	{
		"folke/snacks.nvim",
		priority = 1000, -- load early so vim.notify is snacks.notifier asap
		lazy = false,
		opts = {
			picker = { ui_select = true }, -- also replaces vim.ui.select
			notifier = { enabled = true },
			bigfile = { enabled = true },
			quickfile = { enabled = true },
		},
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

	-- yanky: clipboard history (replaces neoclip). <leader>ty uses snacks picker via vim.ui.select.
	-- Must load early (VeryLazy) so TextYankPost hooks are registered at startup.
	{
		"gbprod/yanky.nvim",
		event = "VeryLazy",
		opts = {
			ring = {
				history_length = 100,
				storage = "shada",
			},
		},
		keys = {
			{ "<leader>ty", "<cmd>YankyRingHistory<cr>", desc = "yank history" },
		},
	},

	-- treesitter: syntax highlighting, indentation, class and function objects
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		config = function()
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					pcall(vim.treesitter.start, args.buf)
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		config = function()
			pcall(function()
				require("nvim-treesitter-textobjects").setup({
					select = {
						enable = true,
						lookahead = true,
						keymaps = {
							["af"] = "@function.outer",
							["if"] = "@function.inner",
							["ac"] = "@class.outer",
							["ic"] = "@class.inner",
							["as"] = { query = "@scope", query_group = "locals" },
						},
					},
				})
			end)
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		config = function()
			require("treesitter-context").setup({ max_lines = 3 })
		end,
	},

	-- blink.cmp: autocomplete (fast Rust-based replacement for nvim-cmp)
	-- Keymaps: <C-Space> complete, <CR> accept, <Tab>/<S-Tab> nav or snippet jump,
	--         <C-e> hide, <C-p>/<C-n> prev/next.
	{
		"saghen/blink.cmp",
		dependencies = { "rafamadriz/friendly-snippets" },
		version = "1.*",
		opts = {
			keymap = { preset = "default" },
			appearance = { nerd_font_variant = "mono" },
			fuzzy = { implementation = IS_SSH and "lua" or "prefer_rust" },
			completion = {
				documentation = { auto_show = true, auto_show_delay_ms = 200 },
				ghost_text = { enabled = true },
				menu = {
					draw = {
						columns = { { "label", "label_description", gap = 1 }, { "kind" }, { "source_name" } },
					},
				},
			},
			sources = {
				default = { "lazydev", "lsp", "path", "snippets", "buffer" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100, -- show lazydev matches above LSP
					},
				},
			},
			signature = { enabled = true },
			cmdline = { enabled = true },
		},
		opts_extend = { "sources.default" },
	},

	-- lazydev: auto-configures lua_ls workspace library when editing nvim config.
	-- Only activates on lua buffers. Feeds completions into blink.cmp via the source above.
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				-- luvit types for vim.uv.* completions
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},

	-- LSP: mason installs servers; nvim-lspconfig ships the per-server default
	-- configs as lsp/<name>.lua on the runtimepath, consumed by vim.lsp.config.
	{
		"williamboman/mason.nvim",
		enabled = not IS_SSH,
		opts = {
			-- Crashdummyy registry provides the `roslyn` LSP package used by roslyn.nvim.
			registries = HAS_DOTNET and {
				"github:mason-org/mason-registry",
				"github:Crashdummyy/mason-registry",
			} or {
				"github:mason-org/mason-registry",
			},
		},
	},
	{ "neovim/nvim-lspconfig" },
	{
		"williamboman/mason-lspconfig.nvim",
		enabled = not IS_SSH,
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
			"saghen/blink.cmp",
		},
		config = function()
			-- C# is handled separately by roslyn.nvim (not listed here).
			local servers = { "gopls", "pyright", "clangd", "lua_ls", "bashls" }

			-- Defaults applied to every server (blink.cmp capabilities).
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})

			-- Per-server overrides. These are deep-merged on top of '*' and the
			-- defaults shipped by nvim-lspconfig in lsp/<name>.lua.
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
						telemetry = { enable = false },
					},
				},
			})

			-- bash-language-server handles zsh on a best-effort basis.
			vim.lsp.config("bashls", {
				filetypes = { "sh", "bash", "zsh" },
			})

			-- mason-lspconfig v2 installs missing servers and calls vim.lsp.enable
			-- for each (automatic_enable defaults to true).
			require("mason-lspconfig").setup({
				ensure_installed = servers,
			})

			-- Buffer-local keymaps when an LSP attaches. nvim 0.11+ defaults:
			-- K (hover), grr (refs), gri (impl), grn (rename), gra (code action),
			-- gO (doc symbols), [d/]d (diag nav), <C-s> (sig help in insert).
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					local map = function(lhs, rhs, desc)
						vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
					end
					map("gd", vim.lsp.buf.definition, "LSP: definition")
					map("gD", vim.lsp.buf.declaration, "LSP: declaration")
				end,
			})
		end,
	},

	-- conform: formatter dispatcher (<leader>f and format-on-save)
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = { "ConformInfo" },
		opts = {
			formatters_by_ft = {
				go = { "goimports", "gofumpt" },
				python = { "ruff_organize_imports", "ruff_format" },
				lua = { "stylua" },
				sh = { "shfmt" },
				bash = { "shfmt" },
				zsh = { "shfmt" },
				cpp = { "clang_format" },
				c = { "clang_format" },
				cs = { "csharpier" },
			},
			format_on_save = function(bufnr)
				if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
					return
				end
				return { timeout_ms = 500, lsp_format = "fallback" }
			end,
		},
	},

	-- mason-tool-installer: ensure formatters/linters/LSPs installed via Mason
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		enabled = not IS_SSH,
		dependencies = { "williamboman/mason.nvim" },
		opts = {
			ensure_installed = HAS_DOTNET and {
				"goimports",
				"gofumpt",
				"ruff",
				"stylua",
				"shfmt",
				"clang-format",
				"csharpier",
				"roslyn", -- C# LSP, consumed by roslyn.nvim
			} or {
				"goimports",
				"gofumpt",
				"ruff",
				"stylua",
				"shfmt",
				"clang-format",
			},
		},
	},

	-- roslyn.nvim: Microsoft's Roslyn-based C# LSP (replaces omnisharp).
	-- Auto-discovers the server installed by Mason via the Crashdummyy registry.
	{
		"seblyng/roslyn.nvim",
		enabled = HAS_DOTNET,
		ft = "cs",
		opts = {},
	},
})
