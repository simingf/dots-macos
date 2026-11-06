local env = require("config.env")

return {

	-- blink.cmp: autocomplete (Rust fuzzy, Lua over SSH).
	-- <C-Space> complete, <CR> accept, <Tab>/<S-Tab> snippet jump, <C-e> hide, <C-p>/<C-n> prev/next
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

	-- lazydev: lua_ls workspace library for nvim config (feeds blink via the source above)
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
}
