local env = require("config.env")

return {

	-- treesitter: syntax highlighting, indentation, class and function objects
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		config = function()
			-- installs into stdpath("data")/site; parsers are vendored on the offline dev box
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
			-- main branch's setup() silently ignores keymaps/enable, so bind by hand
			require("nvim-treesitter-textobjects").setup({ select = { lookahead = true } })
			local sel = require("nvim-treesitter-textobjects.select").select_textobject
			local objs = {
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",
			}
			-- inner objects use `l` (dlf / vlc): `i` is a motion (keymaps.lua) and an x/o map
			-- starting with `i` would make every `i` wait out timeoutlen
			for lhs, obj in pairs(objs) do
				vim.keymap.set({ "x", "o" }, (lhs:gsub("^i", "l")), function()
					sel(obj, "textobjects")
				end, { desc = "textobject " .. obj })
			end
			-- main branch: scope is @local.scope in group "locals"
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

	-- markdown-preview: live browser preview (off on the headless dev box).
	-- build fetches the prebuilt server; lazy builds before sourcing, so force-load or E117.
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
			-- g:mkdp_markdown_css *replaces* the bundled css, so write bundled + overrides to
			-- cache on load: full width (page.css caps #page-ctn at 900px) + rose-pine
			local base = vim.fn.stdpath("data") .. "/lazy/markdown-preview.nvim/app/_static/markdown.css"
			local out = vim.fn.stdpath("cache") .. "/mkdp-markdown.css"
			local css = ""
			local fh = io.open(base, "r")
			if fh then
				css = fh:read("*a")
				fh:close()
			end
			css = css .. "\n#page-ctn{max-width:none!important;padding:8px 5%!important;}\n"
			-- rose-pine prose colors matching glow.yazi's rose-pine.json (THEME.md); code
			-- blocks keep mkdp's highlight.js theme
			css = css .. [[
:root,.markdown-body{--color-canvas-default:#191724;--color-canvas-subtle:#1f1d2e;--color-fg-default:#e0def4;--color-fg-muted:#908caa;--color-fg-subtle:#6e6a86;--color-border-default:#26233a;--color-border-muted:#403d52;--color-accent-fg:#ceacf6;--color-neutral-muted:#26233a;}
body{background:#191724;}
.markdown-body{background:#191724;color:#e0def4;}
.markdown-body h1{display:inline-block;color:#191724;background:#ceacf6;padding:.1em .4em;border-bottom:none;font-weight:700;}
.markdown-body h2{color:#ceacf6;border-bottom:none;font-weight:700;}
.markdown-body h3{color:#9ccfd8;}
.markdown-body h4{color:#ebbcba;}
.markdown-body h5{color:#f6c177;font-weight:400;}
.markdown-body h6{color:#31748f;font-weight:400;}
.markdown-body a{color:#ceacf6;font-weight:700;text-decoration:underline;}
.markdown-body strong{color:#f6c177;}
.markdown-body em{color:#ebbcba;}
.markdown-body del,.markdown-body s{color:#6e6a86;}
.markdown-body code,.markdown-body tt{background:#26233a;color:#eb6f92;}
.markdown-body pre{background:#1f1d2e;}
.markdown-body pre code{background:transparent;color:#e0def4;}
.markdown-body blockquote{color:#908caa;border-left-color:#6e6a86;}
.markdown-body hr{background:#6e6a86;}
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
