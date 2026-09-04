-- set the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- (<leader>w → <C-w> chain is registered as a which-key proxy in the plugin spec below
--  so the popup shows the full <C-w>* hint set; ctrl-w is hard to reach otherwise.)
-- Colemak-DH: hjkl ↔ mnei swap. `i` is remapped only in normal mode — visual and
-- operator-pending keep it as the text-object prefix (vi(, di", ci{, treesitter
-- af/if); in those modes plain `l` still moves right (it's remapped only in normal).
local _nxo = { "n", "x", "o" }
vim.keymap.set(_nxo, "m", "h")
vim.keymap.set(_nxo, "n", "j")
vim.keymap.set(_nxo, "e", "k")
vim.keymap.set("n", "i", "l")
vim.keymap.set({ "n", "x" }, "j", "n")
-- symmetric search repeat: J = prev (else backward search stays on `N`, a different
-- physical row). Join-lines loses its `J` home → moved to <leader>j below (gJ still
-- joins without a space, since the g-prefix builtin ignores the top-level J map).
vim.keymap.set({ "n", "x" }, "J", "N")
vim.keymap.set(_nxo, "k", "e")
vim.keymap.set("n", "l", "i")
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

-- bind 0 to ^ and L to $ (H is taken by arrow.nvim)
vim.keymap.set({ "n", "x", "o" }, "0", "^", { noremap = true, silent = true })
vim.keymap.set({ "n", "x", "o" }, "L", "$", { noremap = true, silent = true })
-- format with conform (falls back to LSP if no formatter is configured for the filetype)
vim.keymap.set({ "n", "x" }, "<leader>f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "format" })
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
