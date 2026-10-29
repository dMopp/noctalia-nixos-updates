#!/bin/sh
# Update check for the nixos-updates service. Changes nothing on the system:
# the updated lock file goes to the plugin data directory, flake.lock and the
# installed Flatpaks stay as they are.
#
#   check.sh <out_dir> <flake_dir> <nixos_configuration> <packages 0|1> <flatpak 0|1>
#
# Prints one line per event for the service (runStream has no exit callback):
#   step <name>             a step starts
#   fail <step> <message>   a step failed, the check goes on where it can
#   done                    finished; the results are in <out_dir>
#
# Result files: new.lock (the lock `nix flake update` would write),
# packages-old.json / packages-new.json (name and version of every
# environment.systemPackages entry plus the kernel), flatpak-installed.tsv,
# flatpak-updates.tsv (installation, application, branch, new version).

set -u
out=$1
dir=$2
cfg=$3
packages=$4
flatpak=$5

nixflags="--extra-experimental-features nix-command --extra-experimental-features flakes"
err="$out/stderr"

# Last stderr lines of the failed command on one line.
fail() {
	printf 'fail %s %s\n' "$1" "$(grep -v '^warning:' "$err" | tail -n 3 | tr '\n\t' '  ')"
}

# Name and version of each package; entries that fail to evaluate (broken,
# unfree without permission) are skipped instead of failing the whole list.
apply='c: let
  pkg = p: let r = builtins.tryEval (
    if p ? pname then { n = p.pname; v = p.version or ""; }
    else let d = builtins.parseDrvName (p.name or ""); in { n = d.name; v = d.version; });
  in if r.success then [ r.value ] else [ ];
  kernel = builtins.tryEval c.boot.kernelPackages.kernel;
in builtins.concatMap pkg (c.environment.systemPackages ++ (if kernel.success then [ kernel.value ] else [ ]))'

# Evaluates the package list for one lock file into $2, unless the lock is the
# same as on the last evaluation ($2.lock keeps a copy of it).
evaluate() {
	lock=$1
	result=$2
	if [ -s "$result" ] && cmp -s "$lock" "$result.lock"; then
		return 0
	fi
	# shellcheck disable=SC2086
	if nix $nixflags eval --json --no-write-lock-file --reference-lock-file "$lock" \
		"$dir#nixosConfigurations.\"$cfg\".config" --apply "$apply" >"$result.tmp" 2>"$err"; then
		mv "$result.tmp" "$result"
		cp "$lock" "$result.lock"
		return 0
	fi
	rm -f "$result.tmp" "$result" "$result.lock"
	return 1
}

if [ -n "$dir" ]; then
	echo "step lock"
	rm -f "$out/new.lock"
	# shellcheck disable=SC2086
	if [ ! -f "$dir/flake.lock" ]; then
		echo "fail lock no-lock"
	elif ! nix $nixflags flake update --flake "$dir" --output-lock-file "$out/new.lock" 2>"$err"; then
		fail lock
	elif [ "$packages" = 1 ]; then
		[ -n "$cfg" ] || cfg=$(cat /proc/sys/kernel/hostname)
		echo "step eval-old"
		if ! evaluate "$dir/flake.lock" "$out/packages-old.json"; then
			fail eval-old
		elif cmp -s "$dir/flake.lock" "$out/new.lock"; then
			# Nothing to update: same lock, same packages.
			cp "$out/packages-old.json" "$out/packages-new.json"
			cp "$out/new.lock" "$out/packages-new.json.lock"
		else
			echo "step eval-new"
			evaluate "$out/new.lock" "$out/packages-new.json" || fail eval-new
		fi
	fi
fi

if [ "$flatpak" = 1 ] && command -v flatpak >/dev/null 2>&1; then
	echo "step flatpak"
	flatpak list --columns=installation,application,branch,version,name >"$out/flatpak-installed.tsv" 2>"$err" || fail flatpak
	: >"$out/flatpak-updates.tsv"
	for inst in system user; do
		if flatpak remote-ls "--$inst" --updates --columns=application,branch,version >"$out/flatpak-$inst.tsv" 2>"$err"; then
			sed "s/^/$inst\t/" "$out/flatpak-$inst.tsv" >>"$out/flatpak-updates.tsv"
		else
			fail flatpak
		fi
		rm -f "$out/flatpak-$inst.tsv"
	done
fi

rm -f "$err"
echo done
