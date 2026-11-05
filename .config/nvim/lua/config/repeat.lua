-- tmux-style repeatable leader maps, like `bind -r` + `repeat-time 300` (.tmux.conf). Used by the
-- buffer-tab keys (plugins/ui.lua) and the window keys (config/keymaps.lua).
--
-- M.group({ [key] = rhs, ... }) returns { [key] = fn }; map each fn on <leader>key.
-- After one fires, a bare tap of any key in its group within 300ms fires again
-- without re-pressing the leader. The bare keys are mapped only while the chain is
-- live (each tap restarts the timer); any other key ends it, restoring their
-- builtin meanings. rhs is an Ex command string or a function.
local M = {}

local timer = vim.uv.new_timer()
local ns = vim.api.nvim_create_namespace("leader_repeat")
local live = {}

local function stop()
	timer:stop()
	vim.on_key(nil, ns)
	for k in pairs(live) do
		pcall(vim.keymap.del, "n", k)
	end
	live = {}
end

function M.group(rhs)
	local fns = {}
	for key, r in pairs(rhs) do
		fns[key] = function()
			stop()
			if type(r) == "function" then
				r()
			else
				vim.cmd(r)
			end
			live = rhs
			for k in pairs(rhs) do
				vim.keymap.set("n", k, fns[k], { nowait = true })
			end
			timer:start(300, 0, vim.schedule_wrap(stop))
			vim.on_key(function(_, typed)
				if typed ~= "" and not rhs[typed] then
					stop()
				end
			end, ns)
		end
	end
	return fns
end

return M
