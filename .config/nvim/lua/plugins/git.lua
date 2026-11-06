return {

	-- git indicators on the left
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = true,
	},

	-- trouble: diagnostics / symbols panels
	{
		"folke/trouble.nvim",
		opts = {},
		cmd = "Trouble",
		keys = {
			{
				"<leader>dd",
				"<cmd>Trouble diagnostics toggle win.size=0.1<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>ds",
				"<cmd>Trouble symbols toggle focus=false win.size=0.25 win.position=right<cr>",
				desc = "Symbols (Trouble)",
			},
		},
	},
}
