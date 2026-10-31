--!nonstrict
-- Tests for the runUpdate command construction, run from the repo root:
--   nix shell nixpkgs#luau -c luau tests/service.luau

-- Inline quote() — mirrors service.luau line 230-232
local function quote(s)
	return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

-- Inline buildRunCommand — mirrors the new runUpdate logic
-- hasSystemdRun parameter simulates noctalia.commandExists("systemd-run")
local function buildRunCommand(updateCmd, terminal, hasSystemdRun)
	if terminal == "" or not hasSystemdRun then
		return "runInTerminal:" .. updateCmd
	end
	local full = "UPDATE_CMD=" .. quote(updateCmd)
		.. " UPDATE_PREFIX=" .. quote(terminal)
		.. " systemd-run --user --scope --collect --quiet sh -c "
		.. quote("exec \"$UPDATE_PREFIX\" \"$UPDATE_CMD\"")
	return full
end

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed = failed + 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end

-- === Empty terminal → fallback ===
check("empty terminal → runInTerminal",
	buildRunCommand("nix flake update", "", true),
	"runInTerminal:nix flake update")

-- === systemd-run not available → fallback ===
check("no systemd-run → runInTerminal",
	buildRunCommand("nix flake update", "kitty -e", false),
	"runInTerminal:nix flake update")

-- === Simple case: kitty with systemd-run ===
check("kitty class with systemd-run",
	buildRunCommand("nix flake update --flake /etc/nixos", "kitty --class nixos-updates -e", true),
	"UPDATE_CMD='nix flake update --flake /etc/nixos' UPDATE_PREFIX='kitty --class nixos-updates -e' systemd-run --user --scope --collect --quiet sh -c 'exec \"$UPDATE_PREFIX\" \"$UPDATE_CMD\"'")

-- === Terminal with spaces (path wrapped in quotes) ===
check("terminal with spaces",
	buildRunCommand("nix flake update", "'/path/to/my terminal' --class test", true),
	"UPDATE_CMD='nix flake update' UPDATE_PREFIX=''\\''/path/to/my terminal'\\'' --class test' systemd-run --user --scope --collect --quiet sh -c 'exec \"$UPDATE_PREFIX\" \"$UPDATE_CMD\"'")

-- === Update command with single quotes ===
check("cmd with single quotes",
	buildRunCommand("sudo nixos-rebuild switch --flake '/etc/nixos#myconfig'", "kitty -e", true),
	"UPDATE_CMD='sudo nixos-rebuild switch --flake '\\''/etc/nixos#myconfig'\\''' UPDATE_PREFIX='kitty -e' systemd-run --user --scope --collect --quiet sh -c 'exec \"$UPDATE_PREFIX\" \"$UPDATE_CMD\"'")

-- === Command with special chars ===
check("cmd with && and spaces",
	buildRunCommand("nix flake update && sudo nixos-rebuild switch", "alacritty -e", true),
	"UPDATE_CMD='nix flake update && sudo nixos-rebuild switch' UPDATE_PREFIX='alacritty -e' systemd-run --user --scope --collect --quiet sh -c 'exec \"$UPDATE_PREFIX\" \"$UPDATE_CMD\"'")

-- === Verify the sh -c body is properly isolated ===
local result = buildRunCommand("nix flake update", "kitty --class nixos-updates -e", true)
-- Note: Luau string.find uses patterns, so '-' must be escaped as '%-'
local checks = {
	["exec body must reference env vars"] = result:find("exec \"%$UPDATE_PREFIX\" \"%$UPDATE_CMD\"") ~= nil,
	["must use systemd-run"] = result:find("systemd%-run") ~= nil,
	["must use --collect for cleanup"] = result:find("%-collect") ~= nil,
	["must use --scope for user scope"] = result:find("%-scope") ~= nil,
}
for reason, ok in pairs(checks) do
	if not ok then
		failed = failed + 1
		print("FAIL structure check: " .. reason)
	end
end

-- === Noctalia API calls are correct ===
-- These verify the logic structure, not actual API calls:
-- 1. If update_command is empty → openSettings()
-- 2. If terminal is empty → runInTerminal(cmd)
-- 3. If systemd-run not available → runInTerminal(cmd)
-- 4. If terminal is set and systemd-run available → runAsync(fullCommand)

print(failed == 0 and "all tests passed" or (tostring(failed) .. " failed"))
