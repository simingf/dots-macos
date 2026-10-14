return {

	-- git indicators on the left
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = true,
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
				"<leader>xs",
				"<cmd>Trouble symbols toggle focus=false win.size=0.25 win.position=right<cr>",
				desc = "Symbols (Trouble)",
			},
		},
	},
}
