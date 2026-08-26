local env = require("config.env")

return {

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
			fuzzy = { implementation = env.IS_SSH and "lua" or "prefer_rust" },
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
}
