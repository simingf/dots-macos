local env = require("config.env")

return {

	-- claudecode.nvim: implements the Claude Code IDE protocol (WebSocket + lock
	-- file in ~/.claude/ide/) so the standalone `claude` CLI can attach to this
	-- nvim and open its file diffs as native diff buffers. Flow: launch nvim,
	-- then in a separate claude pane run /ide and pick this instance. event =
	-- "VeryLazy" + auto_start (default) brings the server up on startup so /ide
	-- finds it. Skipped on the Linux dev box (no internet to fetch the plugin).
	{
		"coder/claudecode.nvim",
		enabled = not env.IS_SSH,
		event = "VeryLazy",
		dependencies = { "folke/snacks.nvim" },
		-- kk launches `claude` and nvim concurrently. claude's startup sweeps
		-- ~/.claude/ide and deletes our freshly-written <port>.lock ~3s later,
		-- leaving the WebSocket server healthy but undiscoverable by /ide. Re-
		-- assert the lock for the running server for the first ~20s until it
		-- sticks (claude only sweeps once, at startup).
		config = function()
			require("claudecode").setup({})
			local cc = require("claudecode")
			local lockfile = require("claudecode.lockfile")
			local uv = vim.uv or vim.loop
			local timer = uv.new_timer()
			local elapsed = 0
			timer:start(
				2000,
				2000,
				vim.schedule_wrap(function()
					elapsed = elapsed + 2000
					local port = cc.state and cc.state.port
					local token = cc.state and cc.state.auth_token
					if port and token then
						local path = lockfile.lock_dir .. "/" .. port .. ".lock"
						if vim.fn.filereadable(path) == 0 then
							pcall(lockfile.create, port, token)
						end
					end
					if elapsed >= 20000 then
						timer:stop()
						timer:close()
					end
				end)
			)
		end,
		keys = {
			{ "<leader>a", nil, desc = "claude code" },
			{ "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "toggle claude terminal" },
			{ "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "add buffer to context" },
			{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "send selection" },
			{ "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "accept diff" },
			{ "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "deny diff" },
		},
	},
}
