-- Startup health check for this config's fragile dependencies — the spots that reach
-- into plugin *internals* or *vendored upstream files* instead of a documented API, and
-- would otherwise fail SILENTLY after a plugin update (guarded to no-op, not error). See
-- FRAGILE.md. Runs once on `User VeryLazy` and only warns when an assumption has broken;
-- `:ConfigHealth` prints the full report (healthy checks included) on demand.
--
-- Scope note: this validates load-bearing *module/API* assumptions (functions & fields
-- that exist at startup). It cannot check picker *instance* fields like `p.list.win.win`
-- or `p.layout.root.win` (those need a live open picker) — those stay "fails silently".
local env = require("config.env")

local M = {}

-- snacks exposes its modules as callable *tables* (a `__call` metamethod), not bare
-- functions — so `Snacks.explorer(...)` / `Snacks.bufdelete(...)` are tables. Accept either.
local function callable(v)
	if type(v) == "function" then
		return true
	end
	local mt = getmetatable(v)
	return type(mt) == "table" and mt.__call ~= nil
end

-- Each check returns nil when healthy, or a short string describing what broke.
-- pcall-wrapped by run(), so a check may index freely.
local checks = {
	{
		name = "snacks explorer API (navigation.lua)",
		fn = function()
			local S = rawget(_G, "Snacks")
			if not (S and S.picker) then
				return "Snacks.picker missing"
			end
			local gone = {}
			if not callable(S.picker.get) then
				gone[#gone + 1] = "picker.get"
			end
			if not (S.picker.util and callable(S.picker.util.path)) then
				gone[#gone + 1] = "picker.util.path"
			end
			if not callable(S.explorer) then
				gone[#gone + 1] = "explorer"
			elseif not callable(S.explorer.reveal) then
				gone[#gone + 1] = "explorer.reveal"
			end
			if not callable(S.bufdelete) then
				gone[#gone + 1] = "bufdelete"
			end
			if #gone > 0 then
				return "Snacks API changed: " .. table.concat(gone, ", ")
			end
		end,
	},
	{
		name = "treesitter main-branch API (treesitter.lua)",
		fn = function()
			local ok, ts = pcall(require, "nvim-treesitter")
			if not (ok and type(ts.install) == "function") then
				return "nvim-treesitter.install missing (main-branch API moved)"
			end
			local ok2, sel = pcall(require, "nvim-treesitter-textobjects.select")
			if not (ok2 and type(sel.select_textobject) == "function") then
				return "textobjects.select.select_textobject missing"
			end
		end,
	},
	{
		name = "claudecode lockfile module (ai.lua)",
		fn = function()
			if env.IS_SSH then
				return -- claudecode disabled on the dev box
			end
			local ok, lockfile = pcall(require, "claudecode.lockfile")
			if not ok then
				return "claudecode.lockfile not require-able"
			end
			if lockfile.lock_dir == nil or type(lockfile.create) ~= "function" then
				return "claudecode.lockfile.{lock_dir,create} changed"
			end
		end,
	},
	{
		name = "markdown-preview bundled CSS (treesitter.lua)",
		fn = function()
			if env.IS_SSH then
				return -- mkdp disabled on the dev box
			end
			local base = vim.fn.stdpath("data") .. "/lazy/markdown-preview.nvim/app/_static/markdown.css"
			if vim.fn.filereadable(base) == 0 then
				return "bundled markdown.css missing → rose-pine md loses its GitHub base typography"
			end
		end,
	},
}

-- report_ok=true → notify healthy + broken (for :ConfigHealth); false → warn only if broken.
function M.run(report_ok)
	local broken, lines = {}, {}
	for _, c in ipairs(checks) do
		local ok, res = pcall(c.fn)
		-- healthy → ok=true, res=nil; broken → ok=true, res=string; threw → ok=false.
		local msg = (not ok) and ("check errored: " .. tostring(res)) or res
		if msg then
			broken[#broken + 1] = ("• %s — %s"):format(c.name, msg)
			lines[#lines + 1] = ("✗ %s: %s"):format(c.name, msg)
		elseif report_ok then
			lines[#lines + 1] = ("✓ %s"):format(c.name)
		end
	end
	if report_ok then
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "config health" })
	elseif #broken > 0 then
		vim.notify(
			"fragile dependency may have broken after a plugin update (see nvim FRAGILE.md):\n"
				.. table.concat(broken, "\n"),
			vim.log.levels.WARN,
			{ title = "config health" }
		)
	end
end

vim.api.nvim_create_user_command("ConfigHealth", function()
	M.run(true)
end, { desc = "report config fragile-dependency health" })

-- run after everything has loaded; grouped clear=true so a re-require doesn't stack it.
-- deferred past VeryLazy because claudecode also loads on VeryLazy — running inline could
-- race ahead of its load and false-warn that claudecode.lockfile isn't require-able.
vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	group = vim.api.nvim_create_augroup("config-healthcheck", { clear = true }),
	callback = function()
		vim.defer_fn(function()
			M.run(false)
		end, 1000)
	end,
})

return M
