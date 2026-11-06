-- Checks the spots that reach into plugin internals / vendored files (FRAGILE.md), which
-- would otherwise fail silently after an update. Warns once after VeryLazy if one broke;
-- `:ConfigHealth` shows the full report.
-- Only startup-visible module/API assumptions; live picker fields (p.list.win.win) can't be.
local env = require("config.env")

local M = {}

-- snacks modules are callable tables (__call), not functions
local function callable(v)
	if type(v) == "function" then
		return true
	end
	local mt = getmetatable(v)
	return type(mt) == "table" and mt.__call ~= nil
end

-- each check returns nil when healthy, else what broke (pcall'd, so index freely)
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
		name = "bufferline Tabpage model (ui.lua: ● on the icon, ✕ kept on unsaved tabs)",
		fn = function()
			local ok, models = pcall(require, "bufferline.models")
			if not (ok and type(models.Tabpage) == "table" and type(models.Tabpage.new) == "function") then
				return "bufferline.models.Tabpage.new missing"
			end
		end,
	},
	{
		name = "snacks image placement internals (ui.lua)",
		fn = function()
			local ok, P = pcall(require, "snacks.image.placement")
			if not ok then
				return "snacks.image.placement not require-able"
			end
			local gone = {}
			for _, f in ipairs({ "update", "error", "state", "wins", "hide", "show" }) do
				if type(P[f]) ~= "function" then
					gone[#gone + 1] = f
				end
			end
			if #gone > 0 then
				return "Placement methods changed: " .. table.concat(gone, ", ")
			end
			local I, C = require("snacks.image.image"), require("snacks.image.convert")
			if type(I.new) ~= "function" or type(I.clear) ~= "function" then
				return "snacks.image.image new/clear changed (stale-image reload)"
			end
			if type(C.convert) ~= "function" then
				return "snacks.image.convert.convert changed (stale-image reload)"
			end
			local U, T = require("snacks.image.util"), require("snacks.image.terminal")
			if type(U.dim) ~= "function" or type(T.size) ~= "function" then
				return "snacks.image util.dim / terminal.size changed (fit-to-window)"
			end
			local function upvalue(fn, name)
				for i = 1, 50 do
					local n, v = debug.getupvalue(fn, i)
					if n == nil or n == name then
						return v
					end
				end
			end
			-- ui.lua wraps C.convert, so the class is an upvalue of the original it captured
			local orig = upvalue(C.convert, "convert")
			local Convert = upvalue(type(orig) == "function" and orig or C.convert, "Convert")
			if type(Convert) ~= "table" or type(Convert._resolve) ~= "function" or type(Convert.ft) ~= "function" then
				return "snacks.image.convert Convert class / _resolve changed (big-PNG downscale)"
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

-- report_ok: list healthy checks too (:ConfigHealth); else warn only if broken
function M.run(report_ok)
	local broken, lines = {}, {}
	for _, c in ipairs(checks) do
		local ok, res = pcall(c.fn)
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

-- deferred past VeryLazy so VeryLazy-loaded plugins are up first
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
