vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- (<leader>v = <C-w> is a which-key proxy, see plugins/ui.lua)

-- ── Colemak-DH motions ─────────────────────────────────────────────
-- hjkl → mnei, and i ↔ l: `l` is insert / the inner-object prefix (dlw, cl", vlw)
local _nxo = { "n", "x", "o" }
vim.keymap.set(_nxo, "m", "h")
vim.keymap.set(_nxo, "n", "j")
vim.keymap.set(_nxo, "e", "k")
vim.keymap.set(_nxo, "i", "l")
vim.keymap.set(_nxo, "l", "i")

-- ── pruned defaults (accident-prone / unused; see KEYBINDS.md) ─────
-- nvim default maps are deleted, builtins <Nop>'d. `in` would make every x/o `i` wait
-- out timeoutlen. [ ] pairs go except diagnostics ([d ]d).
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
-- <C-a>/<C-x> increment, <C-z> suspend, ZZ/ZQ quit, gQ Ex mode, & repeat :s
vim.keymap.set({ "n", "x" }, "<C-a>", "<Nop>")
vim.keymap.set({ "n", "x" }, "<C-x>", "<Nop>")
vim.keymap.set({ "n", "x" }, "<C-z>", "<Nop>")
for _, lhs in ipairs({ "ZZ", "ZQ", "gQ", "&" }) do
	vim.keymap.set("n", lhs, "<Nop>")
end
-- insert <C-a> / <C-e>: line start / end, like zsh
vim.keymap.set("i", "<C-a>", "<Home>", { desc = "line start" })
vim.keymap.set("i", "<C-e>", "<End>", { desc = "line end" })
-- matchit's g% [% ]% a% load after this file, so drop them on VimEnter (% stays)
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

-- ── search ─────────────────────────────────────────────────────────
-- j/J = next/prev match (n is a motion now); join lines → <leader>j (gJ still works)
vim.keymap.set({ "n", "x" }, "j", "n")
vim.keymap.set({ "n", "x" }, "J", "N")
-- 'hlsearch' only while the last normal key was a search key. on_key sees keys after
-- mapping, so j/J/⌘F arrive as n/N//.
vim.on_key(function(key)
	if vim.fn.mode() == "n" then
		local searching = vim.tbl_contains({ "n", "N", "*", "#", "/", "?" }, vim.fn.keytrans(key))
		if vim.o.hlsearch ~= searching then
			vim.o.hlsearch = searching
		end
	end
end, vim.api.nvim_create_namespace("auto_hlsearch"))
vim.keymap.set(_nxo, "k", "e") -- end of word (e is up)
-- h/H belong to arrow.nvim; set marks with `:mark x`

-- ── splits (mirror tmux pane keys) ─────────────────────────────────
-- <leader>{mnei}: move between splits, past nvim's edge into the next tmux pane (nav.lua)
for key, d in pairs({ m = { "h", "L", "left" }, n = { "j", "D", "down" }, e = { "k", "U", "up" }, i = { "l", "R", "right" } }) do
	vim.keymap.set("n", "<leader>" .. key, function()
		if not require("config.nav").move(d[1]) and vim.env.TMUX_PANE and vim.env.DOTFILES_DIR then
			vim.system({ vim.env.DOTFILES_DIR .. "/scripts/tmux-nav.sh", d[2], vim.env.TMUX_PANE })
		end
	end, { silent = true, desc = "win " .. d[3] })
end
-- `\` / `-` split like tmux (shifted = before); new splits start empty and the tree
-- fills the first empty one (tabs.lua)
vim.keymap.set("n", "<leader>\\", "<cmd>vnew<cr>", { silent = true, desc = "vsplit" })
vim.keymap.set("n", "<leader>-", "<cmd>new<cr>", { silent = true, desc = "hsplit" })
vim.keymap.set("n", "<leader>|", "<cmd>leftabove vnew<cr>", { silent = true, desc = "vsplit left" })
vim.keymap.set("n", "<leader>_", "<cmd>aboveleft new<cr>", { silent = true, desc = "hsplit above" })
-- resize M/N/E/I (5 cells, border moves that way), swap [ ], equalize 0, last P, close x.
-- After M/I the resized column (and the explorer) keep their width and the other top-level
-- columns share the rest evenly, like tmux-even-columns.sh keep mode.
local function keep_column(win)
	local layout = vim.fn.winlayout()
	if layout[1] ~= "row" then
		return
	end
	local function first(node)
		while node[1] ~= "leaf" do
			node = node[2][1]
		end
		return node[2]
	end
	local function holds(node)
		if node[1] == "leaf" then
			return node[2] == win
		end
		for _, c in ipairs(node[2]) do
			if holds(c) then
				return true
			end
		end
		return false
	end
	local keep, free, used = {}, {}, #layout[2] - 1 -- separators
	for _, c in ipairs(layout[2]) do
		local w = first(c)
		local tree = c[1] == "leaf" and vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "snacks_layout_box"
		if holds(c) or tree then
			keep[w] = vim.api.nvim_win_get_width(w)
			used = used + keep[w]
		else
			free[#free + 1] = w
		end
	end
	if #free == 0 then
		return
	end
	local each, extra = math.floor((vim.o.columns - used) / #free), (vim.o.columns - used) % #free
	for _ = 1, 2 do -- each set_width moves a neighbour, so a second pass settles them
		for i, w in ipairs(free) do
			vim.api.nvim_win_set_width(w, each + (i <= extra and 1 or 0))
		end
		for w, width in pairs(keep) do
			vim.api.nvim_win_set_width(w, width)
		end
	end
end
local function resize(dir)
	local vert = dir == "m" or dir == "i"
	local far = vert and "l" or "j" -- side whose border moves when one exists
	local grow = (dir == "i" or dir == "n") == (vim.fn.winnr(far) ~= vim.fn.winnr())
	vim.cmd((vert and "vertical " or "") .. "resize " .. (grow and "+5" or "-5"))
	if vert then
		keep_column(vim.api.nvim_get_current_win())
	end
end
for k, m in pairs({
	M = { function() resize("m") end, "resize left" },
	N = { function() resize("n") end, "resize down" },
	E = { function() resize("e") end, "resize up" },
	I = { function() resize("i") end, "resize right" },
	["["] = { function() require("config.tabs").swap(-1) end, "swap split backward" },
	["]"] = { function() require("config.tabs").swap(1) end, "swap split forward" },
}) do
	vim.keymap.set("n", "<leader>" .. k, m[1], { desc = m[2] })
end
vim.keymap.set("n", "<leader>0", "<C-w>=", { desc = "equalize splits" })
vim.keymap.set("n", "<leader>P", "<C-w>p", { desc = "last split" })
vim.keymap.set("n", "<leader>x", function()
	require("config.tabs").close_split()
end, { desc = "close split" })
-- zoom toggle, like tmux ‹pfx›z
vim.keymap.set("n", "<leader>z", function()
	Snacks.zen.zoom()
end, { desc = "zoom split" })
vim.keymap.set({ "n", "x" }, "<leader>j", "J", { desc = "join lines" })

-- ── registers ──────────────────────────────────────────────────────
-- x / X don't clobber the unnamed register
vim.keymap.set({ "n", "x" }, "x", '"_x')
vim.keymap.set({ "n", "x" }, "X", '"_d')
vim.keymap.set({ "n", "x" }, "gy", '"+y', { desc = "yank to clipboard" })
vim.keymap.set("n", "gp", '"+p', { desc = "paste from clipboard" })

-- ── ⌘ keys (sent as <D-…> by scripts/tmux-cmdkey.sh; ⌘V is terminal paste) ──
vim.keymap.set({ "n", "x" }, "<D-a>", "ggVG", { desc = "select all" })
vim.keymap.set("i", "<D-a>", "<Esc>ggVG", { desc = "select all" })
vim.keymap.set("x", "<D-c>", '"+y', { desc = "copy" })
vim.keymap.set("x", "<D-x>", '"+d', { desc = "cut" })
vim.keymap.set("n", "<D-z>", "u", { desc = "undo" })
vim.keymap.set("i", "<D-z>", "<C-o>u", { desc = "undo" })
vim.keymap.set("n", "<D-S-z>", "<C-r>", { desc = "redo" })
vim.keymap.set("i", "<D-S-z>", "<C-o><C-r>", { desc = "redo" })
vim.keymap.set({ "n", "i", "x" }, "<D-s>", "<Cmd>write<CR>", { desc = "write buffer" })
-- ⌘⌫: delete back to the first non-blank (normal mode: through the cursor char); from
-- there, the indent. Like zsh's kill-bol.
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
-- ⇧⌘⌫: clear the line(s) to their indent and insert there (not cc: indentexpr re-indents)
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
-- ⇧←/→, ⇧⌘←/→ select like zsh: start visual from n/i, extend in x. Never onto the newline
-- (⌫ would join lines); a no-op in insert at the line's start / end.
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
vim.keymap.set("i", "<M-BS>", "<C-w>", { desc = "delete word" })
-- mouse drag copies on release (like tmux), staying selected so ⌘X / operators still work
vim.keymap.set("x", "<LeftRelease>", '"+ygv', { desc = "copy mouse selection" })

-- ── misc ───────────────────────────────────────────────────────────
-- 0 = ^, L = $ (H is arrow.nvim)
vim.keymap.set({ "n", "x", "o" }, "0", "^", { noremap = true, silent = true })
vim.keymap.set({ "n", "x", "o" }, "L", "$", { noremap = true, silent = true })
-- format (conform, LSP fallback); `=` like the reindent operator (<leader>f is grep)
vim.keymap.set({ "n", "x" }, "<leader>=", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "format" })
-- browser preview (config/preview.lua)
vim.keymap.set("n", "<leader>p", function()
	require("config.preview").current()
end, { desc = "browser preview" })
-- re-run options/keymaps/autocmds (all idempotent), like tmux ‹pfx›C-r.
-- Plugin specs aren't covered: use `:Lazy reload <plugin>`.
vim.keymap.set("n", "<leader><C-r>", function()
	for _, m in ipairs({ "config.options", "config.keymaps", "config.autocmds" }) do
		package.loaded[m] = nil
		require(m)
	end
	vim.notify("reloaded config (options/keymaps/autocmds)", vim.log.levels.INFO)
end, { desc = "reload nvim config" })
-- rename file (LSP-aware), like tmux ‹pfx›r
vim.keymap.set("n", "<leader>r", function()
	Snacks.rename.rename_file()
end, { desc = "rename file" })
-- format-on-save toggle: :FormatDisable[!] (buffer / global), :FormatEnable
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

-- held right-⌥ (Karabiner) sends <leader> before every key, so <leader>tt arrives as
-- <leader>t<leader>t: map <leader>{prefix}<leader> back to <leader>{prefix} for every
-- multi-key leader map prefix.
vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	once = true,
	callback = function()
		local leader = vim.keycode(vim.g.mapleader)
		local seen = {}
		for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
			if vim.startswith(m.lhs, leader) then
				local prefix, keys, rest = "", {}, m.lhs:sub(#leader + 1)
				while rest ~= "" do -- split into keys: <C-R>, <lt>, or one char
					local k = rest:match("^<[^>]+>") or rest:sub(1, 1)
					keys[#keys + 1], rest = k, rest:sub(#k + 1)
				end
				for i = 1, #keys - 1 do
					prefix = prefix .. keys[i]
					if not seen[prefix] then
						seen[prefix] = true
						vim.keymap.set("n", "<leader>" .. prefix .. "<leader>", "<leader>" .. prefix, {
							remap = true,
							desc = "held-⌥ leader: back to <leader>" .. prefix,
						})
					end
				end
			end
		end
	end,
})
