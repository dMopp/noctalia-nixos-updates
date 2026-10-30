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
# environment.systemPackages entry plus the kernel, with changelog and
# homepage), flatpak-installed.tsv, flatpak-updates.tsv (installation,
# application, branch, new version).

set -u
umask 077
out=$1
dir=$2
cfg=$3
packages=$4
flatpak=$5

err="$out/stderr"
rc=0

# Every external call has a time limit, so the script always ends on its own:
# the service cannot stop a stream it started. Worst case 10 + 2 * 15 + 3 * 3
# = 49 minutes; the service waits longer than that before it gives a run up.
# timeout -k kills what ignores the TERM after 30 seconds. No stdin, so nothing
# can wait for an answer.
limit() {
	minutes=$1
	shift
	timeout -k 30 "${minutes}m" "$@" </dev/null
	rc=$?
	return "$rc"
}

# The updated lock points at code the user has not accepted yet, and it is
# evaluated in the background. So settings that would widen what that code can
# do are off here, whatever nix.conf says: no nixConfig from the flake, no
# builtins.exec. max-jobs 0 without builders: nothing is built; a build the
# evaluation asks for (import from derivation) only comes from a binary cache,
# else the evaluation fails with an error.
run_nix() {
	minutes=$1
	shift
	limit "$minutes" nix \
		--extra-experimental-features nix-command \
		--extra-experimental-features flakes \
		--option accept-flake-config false \
		--option allow-unsafe-native-code-during-evaluation false \
		--option max-jobs 0 \
		--option builders "" \
		"$@"
}

# One line for the service: the last stderr lines without control characters,
# cut to a length the stream takes. Output of a failed command stays in $err,
# only this line reaches the protocol.
fail() {
	if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
		printf 'fail %s timed out\n' "$1"
		return
	fi
	printf 'fail %s %s\n' "$1" "$(grep -v '^warning:' "$err" | tail -n 3 | tr '\n\t' '  ' | tr -d '\000-\037\177' | cut -c1-500)"
}

# Name, version, changelog and homepage of each package; entries that fail to
# evaluate (broken, unfree without permission) are skipped instead of failing
# the whole list, a missing changelog or homepage just stays "".
apply='c: let
  text = x: let r = builtins.tryEval (if builtins.isString x then x else if builtins.isList x && x != [ ] && builtins.isString (builtins.head x) then builtins.head x else ""); in if r.success then r.value else "";
  pkg = p: let
    info = (if p ? pname then { n = p.pname; v = p.version or ""; }
      else let d = builtins.parseDrvName (p.name or ""); in { n = d.name; v = d.version; })
      // { c = text (p.meta.changelog or ""); h = text (p.meta.homepage or ""); };
    r = builtins.tryEval (builtins.deepSeq info info);
  in if r.success then [ r.value ] else [ ];
  kernel = builtins.tryEval c.boot.kernelPackages.kernel;
in builtins.concatMap pkg (c.environment.systemPackages ++ (if kernel.success then [ kernel.value ] else [ ]))'

# Evaluates the package list for one lock file into $2. Always both sides with
# the configuration as it is now, so that an edit of the configuration never
# looks like an update; Nix's own caches keep this cheap when nothing changed.
evaluate() {
	lock=$1
	result=$2
	if run_nix 15 eval --json --no-write-lock-file --reference-lock-file "$lock" \
		"$dir#nixosConfigurations.\"$cfg\".config" --apply "$apply" >"$result.tmp" 2>"$err"; then
		mv "$result.tmp" "$result"
		return 0
	fi
	rm -f "$result.tmp" "$result"
	return 1
}

if [ -n "$dir" ]; then
	echo "step lock"
	rm -f "$out/new.lock" "$out/packages-old.json" "$out/packages-new.json"
	if [ ! -f "$dir/flake.lock" ]; then
		echo "fail lock no-lock"
	elif ! run_nix 10 flake update --flake "$dir" --output-lock-file "$out/new.lock" >/dev/null 2>"$err"; then
		fail lock
	elif [ "$packages" = 1 ]; then
		[ -n "$cfg" ] || cfg=$(cat /proc/sys/kernel/hostname)
		echo "step eval-old"
		if ! evaluate "$dir/flake.lock" "$out/packages-old.json"; then
			fail eval-old
		elif cmp -s "$dir/flake.lock" "$out/new.lock"; then
			# Nothing to update: same lock, same packages.
			cp "$out/packages-old.json" "$out/packages-new.json"
		else
			echo "step eval-new"
			evaluate "$out/new.lock" "$out/packages-new.json" || fail eval-new
		fi
	fi
fi

if [ "$flatpak" = 1 ] && command -v flatpak >/dev/null 2>&1; then
	echo "step flatpak"
	limit 3 flatpak list --columns=installation,application,branch,version,name,origin >"$out/flatpak-installed.tsv" 2>"$err" || fail flatpak
	: >"$out/flatpak-updates.tsv"
	for inst in system user; do
		if limit 3 flatpak remote-ls "--$inst" --updates --columns=application,branch,version >"$out/flatpak-$inst.tsv" 2>"$err"; then
			sed "s/^/$inst\t/" "$out/flatpak-$inst.tsv" >>"$out/flatpak-updates.tsv"
		else
			fail flatpak
		fi
		rm -f "$out/flatpak-$inst.tsv"
	done
fi

rm -f "$err"
echo done
