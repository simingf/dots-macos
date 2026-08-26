local env = require("config.env")

return {

	-- LSP: mason installs servers; nvim-lspconfig ships the per-server default
	-- configs as lsp/<name>.lua on the runtimepath, consumed by vim.lsp.config.
	{
		"williamboman/mason.nvim",
		enabled = not env.IS_SSH,
		opts = {
			-- Crashdummyy registry provides the `roslyn` LSP package used by roslyn.nvim.
			registries = env.HAS_DOTNET and {
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
		enabled = not env.IS_SSH,
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

	-- mason-tool-installer: ensure formatters/linters/LSPs installed via Mason
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		enabled = not env.IS_SSH,
		dependencies = { "williamboman/mason.nvim" },
		opts = {
			ensure_installed = env.HAS_DOTNET and {
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
		enabled = env.HAS_DOTNET,
		ft = "cs",
		opts = {},
	},
}
