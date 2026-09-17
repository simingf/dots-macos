-- On a headless SSH box (Linux devspace) there's no pbcopy/xclip/wl-copy and no
-- $DISPLAY, so nvim's auto-detected clipboard provider is a no-op — `"+y` / `gy`
-- write to a register that never leaves nvim. Route the +/* registers through
-- Neovim's built-in OSC 52 provider instead: the escape sequence rides nvim →
-- tmux (set-clipboard on / allow-passthrough) → ssh → ghostty → macOS clipboard.
-- Locally on macOS we keep pbcopy (bidirectional, no size cap), so gate on the
-- shared IS_SSH runtime guard (this whole tree is byte-identical across hosts).
-- Paste reads the last-yank register rather than round-tripping an OSC 52 read:
-- terminals refuse clipboard-read by default, which would hang `gp` — terminal
-- paste (cmd+v) still works for pulling the Mac clipboard in.
if require("config.env").IS_SSH and vim.fn.has("nvim-0.10") == 1 then
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

-- enable absolute line numbers
vim.opt.number = true
vim.opt.relativenumber = false
-- keep sign column on
vim.opt.signcolumn = "yes"
-- highlight current line
vim.opt.cursorline = true
-- minimal number of screen lines to keep above and below the cursor
vim.opt.scrolloff = 5
-- line wrapping
vim.opt.wrap = true
-- preserve indentation when line wrapping
vim.opt.breakindent = true
-- enable mouse for all modes
vim.opt.mouse = "a"
-- include both lower and upper case for search
vim.opt.ignorecase = true
-- ignore upper case letters unless the search includes upper case letters
vim.opt.smartcase = true
-- disable highlighting the result of the most recent search all the time
vim.opt.hlsearch = false
-- set how many spaces a tab is
vim.opt.tabstop = 4
-- set how many spaces << and >> indent by
vim.opt.shiftwidth = 4
-- enable converting a tab into spaces
vim.opt.expandtab = true
-- disable showing current mode since lualine shows
vim.opt.showmode = false
-- reclaim the empty command-line row below the statusline. It auto-expands back
-- to one line while typing a command (:/ ) or when a message needs to display.
vim.opt.cmdheight = 0
-- enable hexademical colors instead of only 256 colors
vim.opt.termguicolors = true
-- configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true
-- persist undo history across sessions (survives quit/reopen)
vim.opt.undofile = true
-- faster idle response: CursorHold-driven autoread checktime + which-key popup
-- (default 4000ms). Lower = snappier disk-change reloads and hint menus.
vim.opt.updatetime = 250
-- diagnostic config
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
