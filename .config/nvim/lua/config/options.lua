-- Clipboard: off Mac/Windows (= the headless Linux dev box) force nvim's OSC 52 provider
-- so yanks reach the Mac clipboard via tmux -> ssh -> ghostty. Keyed on OS because
-- SSH_CONNECTION is empty under a persistent tmux server, and the box's xsel/$DISPLAY
-- exist but are broken (BadWindow), which fools auto-detect.
-- Paste reads the unnamed register: OSC 52 reads are refused by terminals and would
-- hang `gp` (cmd+v still pastes the Mac clipboard).
if vim.fn.has("mac") == 0 and vim.fn.has("win32") == 0 and vim.fn.has("nvim-0.10") == 1 then
	local osc52 = require("vim.ui.clipboard.osc52")
	local function paste()
		return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
	end
	vim.g.clipboard = {
		name = "OSC 52",
		copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
		paste = { ["+"] = paste, ["*"] = paste },
	}
end

-- UI
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 5
vim.opt.wrap = true
vim.opt.breakindent = true
vim.opt.showmode = false -- lualine shows it
vim.opt.cmdheight = 0 -- expands while typing a command or showing a message
vim.opt.termguicolors = true
vim.opt.splitright = true
vim.opt.splitbelow = true

-- input
vim.opt.mouse = "a"
-- ⇧+arrows start a visual selection, plain arrows end it (GUI-style, same as zsh)
vim.opt.keymodel = "startsel,stopsel"

-- search
vim.opt.ignorecase = true
vim.opt.smartcase = true
-- only lit while searching: keymaps.lua clears it on the first non-search key
vim.opt.hlsearch = true

-- indent
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- misc
vim.opt.undofile = true
-- snappier CursorHold (autoread checktime) and which-key popup (default 4000)
vim.opt.updatetime = 250

-- diagnostics
local signs_text = {
	[vim.diagnostic.severity.ERROR] = "",
	[vim.diagnostic.severity.WARN] = "",
	[vim.diagnostic.severity.INFO] = "",
	[vim.diagnostic.severity.HINT] = "",
}
vim.diagnostic.config({
	virtual_text = false,
	signs = {
		text = signs_text,
		numhl = {
			[vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
			[vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
			[vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
			[vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
		},
	},
	update_in_insert = false,
	underline = true,
	severity_sort = true,
	float = {
		border = "rounded",
		source = true,
	},
})
