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
		-- ~/.claude/ide and deletes our freshly-written <port>.lock, leaving the
		-- WebSocket server healthy but undiscoverable by /ide. Rather than poll
		-- on a timer (racy — a 2s window /ide can fall into, and a fixed cutoff),
		-- watch the lock dir with fs_event and rewrite the lock the instant it
		-- vanishes. Event-driven: no window, no time limit. :ClaudeCodeReIDE
		-- (<leader>ai) is the manual fallback to force re-registration on demand.
		config = function()
			require("claudecode").setup({})
			local cc = require("claudecode")
			local lockfile = require("claudecode.lockfile")
			local uv = vim.uv or vim.loop

			-- Ensure the lock exists for the running server. force=true rewrites
			-- even if present. Returns false when no server is up (nothing to do).
			local function ensure_lock(force)
				local port = cc.state and cc.state.port
				local token = cc.state and cc.state.auth_token
				if not (port and token) then
					return false
				end
				local path = lockfile.lock_dir .. "/" .. port .. ".lock"
				if force or vim.fn.filereadable(path) == 0 then
					pcall(lockfile.create, port, token)
				end
				return true
			end

			vim.fn.mkdir(lockfile.lock_dir, "p")
			local watcher = uv.new_fs_event()
			if watcher then
				pcall(function()
					watcher:start(
						lockfile.lock_dir,
						{},
						vim.schedule_wrap(function()
							ensure_lock(false)
						end)
					)
				end)
			end

			vim.api.nvim_create_user_command("ClaudeCodeReIDE", function()
				if not ensure_lock(true) then
					cc.start() -- server not running; bring it up (also writes the lock)
				end
				vim.notify("claudecode: re-registered for /ide discovery", vim.log.levels.INFO)
			end, { desc = "Re-register nvim for Claude /ide discovery" })
		end,
		keys = {
			{ "<leader>a", nil, desc = "claude code" },
			{ "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "toggle claude terminal" },
			{ "<leader>ai", "<cmd>ClaudeCodeReIDE<cr>", desc = "re-register for /ide discovery" },
			{ "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "add buffer to context" },
			{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "send selection" },
			{ "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "accept diff" },
			{ "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "deny diff" },
		},
	},
}
