-- Runtime host guards, shared by plugin specs via require("config.env").
-- IS_SSH: in an SSH session, skip plugins that need network or ship arch-specific
-- native binaries (Mason, blink.cmp Rust fuzzy). False locally on macOS.
-- HAS_DOTNET: gate the C# / roslyn toolchain. True on the work Mac only.
return {
	IS_SSH = (vim.env.SSH_CONNECTION or "") ~= "",
	HAS_DOTNET = vim.fn.executable("dotnet") == 1,
}
