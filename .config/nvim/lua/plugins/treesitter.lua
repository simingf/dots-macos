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
			-- main branch's setup() only takes { select = { lookahead, ... } } — it has
			-- no keymaps/enable fields (those are silently dropped). Bind manually via
			-- select_textobject in visual + operator-pending modes.
			require("nvim-treesitter-textobjects").setup({ select = { lookahead = true } })
			local sel = require("nvim-treesitter-textobjects.select").select_textobject
			local objs = {
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",
			}
			for lhs, obj in pairs(objs) do
				vim.keymap.set({ "x", "o" }, lhs, function()
					sel(obj, "textobjects")
				end, { desc = "textobject " .. obj })
			end
			-- scope capture is @local.scope in group "locals" on the main branch
			vim.keymap.set({ "x", "o" }, "as", function()
				sel("@local.scope", "locals")
			end, { desc = "textobject scope" })
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
