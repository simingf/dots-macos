return {

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

	-- automatic closing brackets (blink.cmp-aware, LazyVim default)
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
}
