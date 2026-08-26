local env = require("config.env")

return {

	-- treesitter: syntax highlighting, indentation, class and function objects
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		config = function()
			-- main branch installs parser+queries to ~/.local/share/nvim/site/{parser,queries}/.
			-- Gated by env.IS_SSH because Linux dev box has no internet (parsers vendored separately).
			if not env.IS_SSH then
				pcall(function()
					require("nvim-treesitter").install({
						"bash", "c", "c_sharp", "cpp", "go", "lua", "python",
						"toml", "json", "yaml",
						"javascript", "typescript",
						"markdown", "markdown_inline", "latex",
						"vim", "vimdoc",
					})
				end)
			end
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

	-- render-markdown: inline markdown rendering (headings, code blocks, tables, checkboxes)
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = { "markdown" },
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
		opts = {},
	},
}
