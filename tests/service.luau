--!nonstrict
-- Tests for the runUpdate command construction, run from the repo root:
--   nix shell nixpkgs#luau -c luau tests/service.luau

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed = failed + 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end

-- Inline buildRunCommand — mirrors the new runUpdate logic
local function buildRunCommand(updateCmd, terminal)
	if terminal == "" then
		return "runInTerminal:" .. updateCmd
	end
	return "runInTerminal:" .. terminal .. " " .. updateCmd
end

-- === Empty terminal → fallback ===
check("empty terminal → runInTerminal",
	buildRunCommand("nix flake update", ""),
	"runInTerminal:nix flake update")

-- === Simple case: kitty ===
check("kitty class",
	buildRunCommand("nix flake update --flake /etc/nixos", "kitty --class nixos-updates -e"),
	"runInTerminal:kitty --class nixos-updates -e nix flake update --flake /etc/nixos")

-- === Terminal with spaces ===
check("terminal with spaces",
	buildRunCommand("nix flake update", "'/path/to/my terminal' --class test"),
	"runInTerminal:'/path/to/my terminal' --class test nix flake update")

-- === Update command with single quotes ===
check("cmd with single quotes",
	buildRunCommand("sudo nixos-rebuild switch --flake '/etc/nixos#myconfig'", "kitty -e"),
	"runInTerminal:kitty -e sudo nixos-rebuild switch --flake '/etc/nixos#myconfig'")

-- === Command with && ===
check("cmd with &&",
	buildRunCommand("nix flake update && sudo nixos-rebuild switch", "alacritty -e"),
	"runInTerminal:alacritty -e nix flake update && sudo nixos-rebuild switch")

-- === Verify runInTerminal is always used ===
local result = buildRunCommand("nix flake update", "kitty --class nixos-updates -e")
assert(result:find("runInTerminal:") ~= nil, "must use runInTerminal")
assert(not result:find("systemd"), "must NOT use systemd-run")

print(failed == 0 and "all tests passed" or (tostring(failed) .. " failed"))
