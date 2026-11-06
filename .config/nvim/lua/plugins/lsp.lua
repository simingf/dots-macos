local env = require("config.env")

-- One server list for both hosts: mason installs it on the Mac; the Linux box has no
-- internet, so there each server is enabled only if its (vendored) binary is on PATH.
-- C# is roslyn.nvim's.
local servers = { "pyright", "rust_analyzer", "lua_ls", "clangd", "gopls", "bashls" }

return {

	{ "mason-org/mason.nvim", enabled = not env.IS_SSH, opts = {} },

	-- nvim-lspconfig supplies the default lsp/<name>.lua configs; overrides + keys here run on both hosts
	{
		"neovim/nvim-lspconfig",
		dependencies = { "saghen/blink.cmp" },
		config = function()
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})

			-- per-server overrides, deep-merged over '*' and lspconfig's defaults
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
						telemetry = { enable = false },
					},
				},
			})

			-- best-effort zsh support
			vim.lsp.config("bashls", {
				filetypes = { "sh", "bash", "zsh" },
			})

			-- no mason on the box: enable whichever servers are installed
			if env.IS_SSH then
				for _, name in ipairs(servers) do
					local cmd = vim.lsp.config[name] and vim.lsp.config[name].cmd
					if type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1 then
						vim.lsp.enable(name)
					end
				end
			end

			-- on top of nvim's defaults (K, grr, gri, grn, gra, gO, [d ]d, i_<C-s>)
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					local map = function(lhs, rhs, desc)
						vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
					end
					-- one target opens tmux-style (tabs.jump); several → quickfix
					local function via_tabs(fn)
						return function()
							fn({
								on_list = function(o)
									if #o.items == 1 then
										local it = o.items[1]
										require("config.tabs").jump(it.filename, { it.lnum, it.col - 1 })
									else
										vim.fn.setqflist({}, " ", o)
										vim.cmd("botright copen")
									end
								end,
							})
						end
					end
					map("gd", via_tabs(vim.lsp.buf.definition), "LSP: definition")
					map("gD", via_tabs(vim.lsp.buf.declaration), "LSP: declaration")
				end,
			})
		end,
	},

	-- v2: installs missing servers and vim.lsp.enable()s them
	{
		"mason-org/mason-lspconfig.nvim",
		enabled = not env.IS_SSH,
		dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
		-- also installs the C# server (roslyn_ls) where there's dotnet, but only enables `servers`:
		-- roslyn.nvim starts C# itself
		opts = {
			ensure_installed = env.HAS_DOTNET and vim.list_extend({ "roslyn_ls" }, servers) or servers,
			automatic_enable = servers,
		},
	},

	-- roslyn.nvim: C# LSP; runs `roslyn-language-server` (Mason on the Mac, vendored on the box).
	-- cond, not enabled, so lazy still installs it on hosts without dotnet (→ vendored to the box).
	{
		"seblyng/roslyn.nvim",
		cond = env.HAS_DOTNET,
		ft = "cs",
		opts = {},
	},
}
