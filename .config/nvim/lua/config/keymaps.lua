-- set the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- (<leader>w → <C-w> chain is registered as a which-key proxy in the plugin spec below
--  so the popup shows the full <C-w>* hint set; ctrl-w is hard to reach otherwise.)
-- Colemak-DH: hjkl ↔ mnei swap, and i ↔ l everywhere (normal / visual / operator-
-- pending): `i` moves right, `l` does whatever `i` did — insert in normal mode, the
-- inner-text-object prefix after an operator or in visual (dlw, cl", yl(, vlw;
-- treesitter dlf / vlc, see plugins/treesitter.lua).
local _nxo = { "n", "x", "o" }
vim.keymap.set(_nxo, "m", "h")
vim.keymap.set(_nxo, "n", "j")
vim.keymap.set(_nxo, "e", "k")
vim.keymap.set(_nxo, "i", "l")
vim.keymap.set(_nxo, "l", "i")
-- Prune keys that only cause accidents or never get used. nvim's own default maps
-- (set before this file runs) are deleted; built-in commands are <Nop>'d.
--   - syntax-node selection (an / in — `in` would also make every x/o `i` wait out
--     timeoutlen — plus [n ]n [N ]N)
--   - [ / ] list pairs for the arglist, tags, location list, quickfix and buffers
--     ([d ]d [D ]D diagnostics stay)
for _, mode in ipairs({ "x", "o" }) do
	pcall(vim.keymap.del, mode, "an")
	pcall(vim.keymap.del, mode, "in")
end
for _, lhs in ipairs({ "[n", "]n", "[N", "]N" }) do
	pcall(vim.keymap.del, "x", lhs)
end
for _, c in ipairs({ "a", "A", "t", "T", "<C-T>", "l", "L", "<C-L>", "q", "Q", "<C-Q>", "b", "B" }) do
	pcall(vim.keymap.del, "n", "[" .. c)
	pcall(vim.keymap.del, "n", "]" .. c)
end
--   - <C-a>/<C-x> (±1 the number under the cursor; <C-a> is "line start" in zsh),
--     <C-z> (suspend nvim), ZZ / ZQ (quit), gQ (Ex mode), & (repeat last :s)
vim.keymap.set({ "n", "x" }, "<C-a>", "<Nop>")
vim.keymap.set({ "n", "x" }, "<C-x>", "<Nop>")
vim.keymap.set({ "n", "x" }, "<C-z>", "<Nop>")
for _, lhs in ipairs({ "ZZ", "ZQ", "gQ", "&" }) do
	vim.keymap.set("n", lhs, "<Nop>")
end
-- insert <C-a> / <C-e>: line start / end like zsh (were: re-insert last text / copy the
-- char below)
vim.keymap.set("i", "<C-a>", "<Home>", { desc = "line start" })
vim.keymap.set("i", "<C-e>", "<End>", { desc = "line end" })
-- matchit's extras (g% [% ]% a%) are defined by a runtime plugin that loads after
-- this file, so drop them once startup is done; plain % stays
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		for _, lhs in ipairs({ "g%", "[%", "]%" }) do
			for _, mode in ipairs({ "n", "x", "o" }) do
				pcall(vim.keymap.del, mode, lhs)
			end
		end
		pcall(vim.keymap.del, "x", "a%")
	end,
})
vim.keymap.set({ "n", "x" }, "j", "n")
-- symmetric search repeat: J = prev (else backward search stays on `N`, a different
-- physical row). Join-lines loses its `J` home → moved to <leader>j below (gJ still
-- joins without a space, since the g-prefix builtin ignores the top-level J map).
vim.keymap.set({ "n", "x" }, "J", "N")
-- auto-clear search highlights: keep 'hlsearch' on only while the last normal-mode key
-- was a search key. on_key sees keys *after* mappings, so j/J/⌘F arrive as n/N//.
vim.on_key(function(key)
	if vim.fn.mode() == "n" then
		local searching = vim.tbl_contains({ "n", "N", "*", "#", "/", "?" }, vim.fn.keytrans(key))
		if vim.o.hlsearch ~= searching then
			vim.o.hlsearch = searching
		end
	end
end, vim.api.nvim_create_namespace("auto_hlsearch"))
vim.keymap.set(_nxo, "k", "e")
-- `h`/`H` are claimed by arrow.nvim (buffer / global UI); use `:mark x` to set marks.
-- pane switching: <leader>{mnei} matches the colemak-swap movement keys
vim.keymap.set("n", "<leader>m", "<C-w>h", { silent = true, desc = "win left" })
vim.keymap.set("n", "<leader>n", "<C-w>j", { silent = true, desc = "win down" })
vim.keymap.set("n", "<leader>e", "<C-w>k", { silent = true, desc = "win up" })
vim.keymap.set("n", "<leader>i", "<C-w>l", { silent = true, desc = "win right" })
-- splits: match tmux (`\` = vertical divider, `-` = horizontal divider)
vim.keymap.set("n", "<leader>\\", "<cmd>vsplit<cr>", { silent = true, desc = "vsplit" })
vim.keymap.set("n", "<leader>-", "<cmd>split<cr>", { silent = true, desc = "hsplit" })
-- join lines (J reclaimed for search-prev above)
vim.keymap.set({ "n", "x" }, "<leader>j", "J", { desc = "join lines" })
-- prevent x or X from modifying the internal register
vim.keymap.set({ "n", "x" }, "x", '"_x')
vim.keymap.set({ "n", "x" }, "X", '"_d')
-- yank and paste from clipboard
vim.keymap.set({ "n", "x" }, "gy", '"+y', { desc = "yank to clipboard" })
vim.keymap.set("n", "gp", '"+p', { desc = "paste from clipboard" })
-- ⌘ keys, matching zsh / Claude Code: tmux (scripts/tmux-cmdkey.sh) delivers ⌘A/C/X/Z/⇧Z/S
-- / ⌘←/→ as <D-…> keys (⌘V is the terminal's own paste).
vim.keymap.set({ "n", "x" }, "<D-a>", "ggVG", { desc = "select all" })
vim.keymap.set("i", "<D-a>", "<Esc>ggVG", { desc = "select all" })
vim.keymap.set("x", "<D-c>", '"+y', { desc = "copy" })
vim.keymap.set("x", "<D-x>", '"+d', { desc = "cut" })
vim.keymap.set("n", "<D-z>", "u", { desc = "undo" })
vim.keymap.set("i", "<D-z>", "<C-o>u", { desc = "undo" })
vim.keymap.set("n", "<D-S-z>", "<C-r>", { desc = "redo" })
vim.keymap.set("i", "<D-S-z>", "<C-o><C-r>", { desc = "redo" })
vim.keymap.set({ "n", "i", "x" }, "<D-s>", "<Cmd>write<CR>", { desc = "write buffer" })
-- ⌘⌫ deletes back to the first non-blank — in normal mode through the cursor char (what ⇧⌘← selects) —
-- and from the first non-blank it deletes the indent, like zsh's kill-bol
local function delete_to_line_start(inclusive)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local indent = #line:match("^%s*")
	local from, to = 0, col
	if col > indent then
		from = indent
		to = inclusive and col + #vim.fn.strcharpart(line:sub(col + 1), 0, 1) or col
	end
	vim.api.nvim_buf_set_text(0, row - 1, from, row - 1, to, {})
	vim.api.nvim_win_set_cursor(0, { row, from })
end
vim.keymap.set("n", "<D-BS>", function() delete_to_line_start(true) end, { desc = "delete to line start" })
vim.keymap.set("i", "<D-BS>", function() delete_to_line_start(false) end, { desc = "delete to line start" })
vim.keymap.set("x", "<D-BS>", "d", { desc = "delete selection" })
vim.keymap.set("x", "<BS>", "d", { desc = "delete selection" })
-- ⇧⌘⌫ clears the line(s) down to their indent and types there, like zsh / Claude Code clearing their input
-- (not cc: indentexpr would recompute the indent)
local function clear_lines()
	local first, last = vim.fn.line("."), vim.fn.line("v")
	if first > last then
		first, last = last, first
	end
	local insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
	if not insert then
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	end
	local indent = vim.fn.getline(first):match("^%s*")
	vim.api.nvim_buf_set_lines(0, first - 1, last, false, { indent })
	vim.api.nvim_win_set_cursor(0, { first, #indent })
	if not insert then
		vim.cmd("startinsert!")
	end
end
vim.keymap.set({ "n", "i", "x" }, "<D-S-BS>", clear_lines, { desc = "clear line" })
vim.keymap.set("n", "<D-f>", "/", { desc = "find" })
vim.keymap.set({ "i", "x" }, "<D-f>", "<Esc>/", { desc = "find" })
vim.keymap.set({ "n", "i", "x" }, "<D-p>", function()
	Snacks.picker.files()
end, { desc = "find files" })
vim.keymap.set("n", "<D-/>", "gcc", { remap = true, desc = "toggle comment" })
vim.keymap.set("x", "<D-/>", "gc", { remap = true, desc = "toggle comment" })
vim.keymap.set("i", "<D-/>", "<Cmd>normal gcc<CR>", { desc = "toggle comment" })
vim.keymap.set("n", "<D-]>", ">>", { desc = "indent" })
vim.keymap.set("n", "<D-[>", "<<", { desc = "outdent" })
vim.keymap.set("x", "<D-]>", ">gv", { desc = "indent" })
vim.keymap.set("x", "<D-[>", "<gv", { desc = "outdent" })
vim.keymap.set("i", "<D-]>", "<C-t>", { desc = "indent" })
vim.keymap.set("i", "<D-[>", "<C-d>", { desc = "outdent" })
vim.keymap.set({ "n", "x" }, "<D-Left>", "^", { desc = "line start" })
vim.keymap.set("n", "<D-Right>", "$", { desc = "line end" })
vim.keymap.set("x", "<D-Right>", "g_", { desc = "line end" }) -- $ would also select the newline
vim.keymap.set("i", "<D-Left>", "<C-o>^", { desc = "line start" })
vim.keymap.set("i", "<D-Right>", "<End>", { desc = "line end" })
-- ⇧←/→ and ⇧⌘←/→ select, like zsh's prompt: start visual from normal / insert, extend it in visual.
-- Never past the last char (visual lets the cursor onto the newline, which ⌫ would then join), and in
-- insert mode nothing to select at the line's start / end is a no-op.
local function at_eol()
	return vim.fn.col(".") >= vim.fn.col("$") - 1
end
local function at_bol()
	return vim.fn.col(".") == 1
end
local function past_eol()
	return vim.fn.col(".") >= vim.fn.col("$")
end
local function map_expr(mode, lhs, fn, desc)
	vim.keymap.set(mode, lhs, fn, { expr = true, desc = desc })
end
map_expr("n", "<S-Left>", function() return "vh" end, "select left")
map_expr("n", "<S-Right>", function() return at_eol() and "v<Ignore>" or "vl" end, "select right")
vim.keymap.set("x", "<S-Left>", "h", { desc = "select left" })
map_expr("x", "<S-Right>", function() return at_eol() and "" or "l" end, "select right")
map_expr("i", "<S-Left>", function() return at_bol() and "" or "<Left><C-o>v" end, "select left")
map_expr("i", "<S-Right>", function() return past_eol() and "" or "<C-o>v" end, "select right")
vim.keymap.set("n", "<D-S-Left>", "v^", { desc = "select to line start" })
vim.keymap.set("n", "<D-S-Right>", "vg_", { desc = "select to line end" })
vim.keymap.set("x", "<D-S-Left>", "^", { desc = "select to line start" })
vim.keymap.set("x", "<D-S-Right>", "g_", { desc = "select to line end" })
map_expr("i", "<D-S-Left>", function() return at_bol() and "" or "<Left><C-o>v^" end, "select to line start")
map_expr("i", "<D-S-Right>", function() return past_eol() and "" or "<C-o>vg_" end, "select to line end")
-- ⌥⌫ deletes a word, like zsh / Claude Code
vim.keymap.set("i", "<M-BS>", "<C-w>", { desc = "delete word" })
-- a mouse drag copies on release, like a tmux selection in zsh / Claude Code, but stays
-- selected (gv) so ⌘X or an operator can still act on it
vim.keymap.set("x", "<LeftRelease>", '"+ygv', { desc = "copy mouse selection" })

-- bind 0 to ^ and L to $ (H is taken by arrow.nvim)
vim.keymap.set({ "n", "x", "o" }, "0", "^", { noremap = true, silent = true })
vim.keymap.set({ "n", "x", "o" }, "L", "$", { noremap = true, silent = true })
-- format with conform (falls back to LSP if no formatter is configured for the filetype)
vim.keymap.set({ "n", "x" }, "<leader>f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "format" })
-- browser preview of the current file: md → markdown-preview (themed), else → live-preview.
-- same routing as the snacks-explorer `o` key (see config.preview).
vim.keymap.set("n", "<leader>p", function()
	require("config.preview").current()
end, { desc = "browser preview" })
-- reload the config modules live (options/keymaps/autocmds) so edits to them take
-- effect without restarting nvim: drop them from the module cache and re-require.
-- Safe because each is idempotent on re-run (keymaps/options overwrite; autocmds
-- use clear=true augroups). Plugin *spec* changes aren't covered by this — lazy runs
-- a plugin's config once; use `:Lazy reload <plugin>` (e.g. snacks.nvim) for those.
vim.keymap.set("n", "<leader>r", function()
	for _, m in ipairs({ "config.options", "config.keymaps", "config.autocmds" }) do
		package.loaded[m] = nil
		require(m)
	end
	vim.notify("reloaded config (options/keymaps/autocmds)", vim.log.levels.INFO)
end, { desc = "reload nvim config" })
-- toggle format-on-save: :FormatDisable (buffer) or :FormatDisable! (global), :FormatEnable to re-enable
vim.api.nvim_create_user_command("FormatDisable", function(args)
	if args.bang then
		vim.g.disable_autoformat = true
	else
		vim.b.disable_autoformat = true
	end
end, { desc = "Disable format-on-save", bang = true })
vim.api.nvim_create_user_command("FormatEnable", function()
	vim.b.disable_autoformat = false
	vim.g.disable_autoformat = false
end, { desc = "Re-enable format-on-save" })
