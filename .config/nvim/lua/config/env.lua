-- Runtime host guards for plugin specs.
-- IS_SSH: skip plugins needing network or native binaries (Mason, blink.cmp Rust fuzzy).
-- HAS_DOTNET: gate the C# / roslyn toolchain (work Mac only).
return {
	IS_SSH = (vim.env.SSH_CONNECTION or "") ~= "",
	HAS_DOTNET = vim.fn.executable("dotnet") == 1,
}
