return {

	-- flash: s / S jump
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
		},
	},

	-- arrow: file bookmarks (H) and in-file marks (h)
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

	-- yanky: yank history (<leader>ty). VeryLazy so its TextYankPost hook catches every yank.
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

	-- auto-close brackets
	{
		"echasnovski/mini.pairs",
		event = "InsertEnter",
		config = true,
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

	-- recorder: macros in slots a/b/c
	{
		"chrisgrieser/nvim-recorder",
		keys = {
			-- must match `mapping` below
			{ "q", desc = " Start Recording" },
			{ "Q", desc = " Play Recording" },
			{ "<C-q>", desc = " Switch Recording Slot" },
			{ "cq", desc = " Edit Recording" },
			{ "dq", desc = " Delete All Recordings" },
		},
		config = function()
			require("recorder").setup({
				mapping = {
					startStopRecording = "q",
					playMacro = "Q",
					switchSlot = "<C-q>",
					editMacro = "cq",
					deleteAllMacros = "dq",
				},
				-- cleared on startup
				slots = { "a", "b", "c" },
				clear = true,
			})
			-- setup() always maps yq and ## too; drop them (## shadows `#`)
			for _, lhs in ipairs({ "yq", "##" }) do
				pcall(vim.keymap.del, "n", lhs)
			end
		end,
	},
}
