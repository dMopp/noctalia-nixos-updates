--!nonstrict
-- Tests for the command the Update button starts with `terminal` set, run from
-- the repo root:
--   nix shell nixpkgs#luau -c luau tests/service.luau

local diff = require("../nixos-updates/lib/diff")

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed += 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end

check("kitty class",
	diff.terminalCommand("kitty --class nixos-updates -e", "nrs --update"),
	"kitty --class nixos-updates -e sh -lc 'nrs --update'")

-- All of it in the terminal, not `a` in it and `b` in the shell around it
check("&& stays inside the argument",
	diff.terminalCommand("alacritty -e", "nix flake update && sudo nixos-rebuild switch"),
	"alacritty -e sh -lc 'nix flake update && sudo nixos-rebuild switch'")

check("single quotes in the update command",
	diff.terminalCommand("kitty -e", "sudo nixos-rebuild switch --flake '/etc/nixos#myconfig'"),
	"kitty -e sh -lc 'sudo nixos-rebuild switch --flake '\\''/etc/nixos#myconfig'\\'''")

check("prefix keeps its own quoting",
	diff.terminalCommand("'/path/to/my terminal' --class test", "true"),
	"'/path/to/my terminal' --class test sh -lc 'true'")

print(failed == 0 and "all tests passed" or (tostring(failed) .. " failed"))
