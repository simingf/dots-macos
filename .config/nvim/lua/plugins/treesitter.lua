local env = require("config.env")

return {

	-- treesitter: syntax highlighting, indentation, class and function objects
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		config = function()
			-- main branch installs parser+queries to ~/.local/share/nvim/site/{parser,queries}/.
			-- Gated by env.IS_SSH because Linux dev box has no internet (parsers vendored separately).
			if not env.IS_SSH then
				pcall(function()
					require("nvim-treesitter").install({
						"bash", "c", "c_sharp", "cpp", "go", "lua", "python",
						"toml", "json", "yaml",
						"javascript", "typescript",
						"markdown", "markdown_inline", "latex",
						"vim", "vimdoc",
					})
				end)
			end
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					pcall(vim.treesitter.start, args.buf)
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		config = function()
			-- main branch's setup() only takes { select = { lookahead, ... } } — it has
			-- no keymaps/enable fields (those are silently dropped). Bind manually via
			-- select_textobject in visual + operator-pending modes.
			require("nvim-treesitter-textobjects").setup({ select = { lookahead = true } })
			local sel = require("nvim-treesitter-textobjects.select").select_textobject
			local objs = {
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",
			}
			for lhs, obj in pairs(objs) do
				vim.keymap.set({ "x", "o" }, lhs, function()
					sel(obj, "textobjects")
				end, { desc = "textobject " .. obj })
			end
			-- scope capture is @local.scope in group "locals" on the main branch
			vim.keymap.set({ "x", "o" }, "as", function()
				sel("@local.scope", "locals")
			end, { desc = "textobject scope" })
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		config = function()
			require("treesitter-context").setup({ max_lines = 3 })
		end,
	},

	-- markview: in-buffer markdown/latex rendering (headings, code, tables, callouts).
	-- author recommends against lazy-loading (late attach can skip the first buffer), so
	-- lazy=false; loads after the treesitter/devicons deps for parsers + icons.
	{
		"OXY2DEV/markview.nvim",
		lazy = false,
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
		config = function()
			require("markview").setup()
			-- iris-forward headings mirroring glow.yazi (THEME.md): h1 base-on-iris label,
			-- then iris / foam / rose / gold / pine. markview ignores its `highlight_groups`
			-- spec key in this version; the working path is merging a `heading` override into
			-- markview.highlights.groups — its own re-applies (render / ColorScheme call
			-- highlights.setup() → create() from the merged table) then preserve it.
			local hl = require("markview.highlights")
			local fg = { "#191724", "#ceacf6", "#9ccfd8", "#ebbcba", "#f6c177", "#31748f" }
			local headings = function()
				local out = {}
				for h = 1, 6 do
					local v = h == 1 and { fg = fg[1], bg = "#ceacf6", bold = true }
						or { fg = fg[h], bold = h <= 4 }
					table.insert(out, { group_name = ("MarkviewHeading%d"):format(h), value = v })
					table.insert(out, {
						group_name = ("MarkviewHeading%dSign"):format(h),
						value = { link = ("MarkviewPalette%dSign"):format(h) },
					})
				end
				return out
			end
			hl.setup({ heading = headings })
			-- re-merge after rose-pine reloads (it clears custom groups on ColorScheme),
			-- mirroring the snacks explorer pattern in ui.lua.
			vim.api.nvim_create_autocmd("ColorScheme", { callback = function()
				hl.setup({ heading = headings })
			end })
		end,
	},

	-- markdown-preview: live browser preview (real HTML tables wrap per-column).
	-- enabled off on the headless Linux dev box (no browser, no internet for the build).
	-- build downloads the prebuilt server binary (no node/yarn toolchain needed). lazy runs
	-- build before the plugin is sourced, so force-load first or mkdp#util#install is E117.
	{
		"iamcco/markdown-preview.nvim",
		enabled = not env.IS_SSH,
		cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
		ft = { "markdown" },
		build = function()
			vim.cmd("Lazy! load markdown-preview.nvim")
			vim.fn["mkdp#util#install"]()
		end,
		config = function()
			vim.g.mkdp_theme = "dark"
			-- Widen the preview: mkdp hard-caps #page-ctn at 900px (app/_static/page.css).
			-- g:mkdp_markdown_css *replaces* the bundled markdown.css, so regenerate it as
			-- (bundled css + width override) on load — keeps GitHub typography current across
			-- plugin updates without vendoring a CSS copy into the repo.
			local base = vim.fn.stdpath("data") .. "/lazy/markdown-preview.nvim/app/_static/markdown.css"
			local out = vim.fn.stdpath("cache") .. "/mkdp-markdown.css"
			local css = ""
			local fh = io.open(base, "r")
			if fh then
				css = fh:read("*a")
				fh:close()
			end
			css = css .. "\n#page-ctn{max-width:none!important;padding:8px 5%!important;}\n"
			-- rose-pine (THEME.md): recolor prose chrome to match markview + glow.yazi.
			-- fenced-code syntax keeps mkdp's default highlight.js theme (same split as glow).
			css = css .. [[
:root,.markdown-body{--color-canvas-default:#191724;--color-canvas-subtle:#1f1d2e;--color-fg-default:#e0def4;--color-fg-muted:#908caa;--color-fg-subtle:#6e6a86;--color-border-default:#26233a;--color-border-muted:#403d52;--color-accent-fg:#ceacf6;--color-neutral-muted:#26233a;}
body{background:#191724;}
.markdown-body{background:#191724;color:#e0def4;}
.markdown-body h1,.markdown-body h2{color:#ceacf6;border-bottom-color:#26233a;}
.markdown-body h3{color:#9ccfd8;}
.markdown-body h4{color:#ebbcba;}
.markdown-body h5{color:#f6c177;}
.markdown-body h6{color:#31748f;}
.markdown-body a{color:#ceacf6;}
.markdown-body strong{color:#f6c177;}
.markdown-body em{color:#ebbcba;}
.markdown-body code,.markdown-body tt{background:#26233a;color:#eb6f92;}
.markdown-body pre{background:#1f1d2e;}
.markdown-body pre code{background:transparent;color:#e0def4;}
.markdown-body blockquote{color:#908caa;border-left-color:#6e6a86;}
.markdown-body hr{background:#26233a;}
.markdown-body table tr{background:#191724;border-top-color:#26233a;}
.markdown-body table tr:nth-child(2n){background:#1f1d2e;}
.markdown-body table th,.markdown-body table td{border-color:#26233a;}
]]
			local w = io.open(out, "w")
			if w then
				w:write(css)
				w:close()
				vim.g.mkdp_markdown_css = out
			end
		end,
	},
}
