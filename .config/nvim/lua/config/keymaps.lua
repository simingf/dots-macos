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
-- nvim 0.12's built-in `in` (select child node) → `ln`, matching the swap
-- (an x/o-mode map starting with `i` would make every `i` there wait out timeoutlen)
for _, mode in ipairs({ "x", "o" }) do
	local child_node = vim.fn.maparg("in", mode, false, true)
	if child_node.callback then
		vim.keymap.del(mode, "in")
		vim.keymap.set(mode, "ln", child_node.callback, { desc = child_node.desc })
	end
end
vim.keymap.set({ "n", "x" }, "j", "n")
-- symmetric search repeat: J = prev (else backward search stays on `N`, a different
-- physical row). Join-lines loses its `J` home → moved to <leader>j below (gJ still
-- joins without a space, since the g-prefix builtin ignores the top-level J map).
vim.keymap.set({ "n", "x" }, "J", "N")
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
vim.keymap.set("n", "<D-BS>", "dd", { desc = "delete line" })
vim.keymap.set("i", "<D-BS>", "<C-u>", { desc = "delete to line start" })
vim.keymap.set("x", "<D-BS>", "d", { desc = "delete selection" })
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
vim.keymap.set({ "n", "x" }, "<D-Right>", "$", { desc = "line end" })
vim.keymap.set("i", "<D-Left>", "<C-o>^", { desc = "line start" })
vim.keymap.set("i", "<D-Right>", "<End>", { desc = "line end" })
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
