--!nonstrict
-- Tests for the pure comparisons, run from the repo root:
--   nix shell nixpkgs#luau -c luau tests/diff.luau

local diff = require("../nixos-updates/lib/diff")

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed += 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end

-- safeUrl
for _, url in ipairs({
	"https://github.com/cli/cli/releases/tag/v2.103.2",
	"https://downloads.isc.org/isc/bind9/cur/9.20/doc/arm/html/notes.html#notes-for-bind-9-20-30",
	"https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP.md#19860",
	"https://gitlab.freedesktop.org/upower/upower/-/blob/v1.91.5/NEWS",
	"http://example.org",
	"https://host:8443/x",
	"https://host:8443",
	"https://example.org?a=1&b=2",
	"https://mastodon.social/@user",
	"https://example.org/a%20b",
}) do
	check("allow " .. url, diff.safeUrl(url), url)
end
for _, url in ipairs({
	"file:///etc/passwd",
	"/home/x/evil.desktop",
	"--help",
	"-x",
	"javascript:alert(1)",
	"https://",
	"https://a b",
	"https://a.org/b c",
	"https://github.com@evil.org/",
	"https://user:pw@evil.org/",
	"https://a.org:evil",
	"https://-a.org/",
	"https://a.org/$(id)",
	"https://a.org/`id`",
	"https://a.org/;id",
	"https://a.org/'x",
	'https://a.org/"x',
	"https://a.org/x\ny",
	"https://a.org/|x",
	"https://a.org/<x>",
	"https://a.org/\\x",
	"HTTPS://a.org",
	"https://a.org/" .. string.rep("x", 2100),
	"",
}) do
	check("deny " .. url, diff.safeUrl(url), nil)
end
check("deny non-string", diff.safeUrl(5), nil)
check("deny nil", diff.safeUrl(nil), nil)

-- packages
local rows = diff.packages(
	{ { n = "gh", v = "1", c = "", h = "" }, { n = "gone", v = "1", c = "", h = "https://github.com/o/gone" }, { n = "same", v = "1" } },
	{ { n = "gh", v = "2", c = "https://x.org/r", h = "" }, { n = "fresh", v = "3", c = "file:///etc/passwd", h = "" }, { n = "same", v = "1" } }
)
check("packages count", #rows, 3)
check("added", rows[1].name .. rows[1].kind .. rows[1].new, "freshadded3")
check("unsafe changelog gets no link", rows[1].changes, nil)
check("changed", rows[2].name .. rows[2].kind .. rows[2].old .. rows[2].new, "ghchanged12")
check("changed link", rows[2].changes, "https://x.org/r")
check("removed", rows[3].name .. rows[3].kind, "goneremoved")
check("releases fallback", rows[3].changes, "https://github.com/o/gone/releases")
check("releases kind", rows[3].changesKind, "releases")

-- several versions of one name
rows = diff.packages({ { n = "fuse", v = "2.9.9" }, { n = "fuse", v = "3.18.2" } }, { { n = "fuse", v = "3.18.2" } })
check("multi version", rows[1].old .. ">" .. rows[1].new, "2.9.9, 3.18.2>3.18.2")

-- inputs
local function lock(nodes)
	return { root = "root", version = 7, nodes = nodes }
end
local old = lock({
	root = { inputs = { a = "a", ignored = "i", follows = { "a" }, tar = "t", private = "p", self = "s" } },
	a = { locked = { narHash = "h1", rev = "aaaaaaaaaa", lastModified = 100 }, original = { type = "github", owner = "o", repo = "r", ref = "main" } },
	i = { locked = { narHash = "h1", rev = "iiiiiiiiii" }, original = { type = "github", owner = "o", repo = "i" } },
	t = { locked = { narHash = "h1", url = "https://releases.nixos.org/nixos/unstable/nixos-1.a/nixexprs.tar.zst" }, original = { type = "tarball", url = "https://channels.nixos.org/x" } },
	p = { locked = { narHash = "h1", rev = "pppppppppp" }, original = { type = "git", url = "https://token123@git.example.org/r.git" } },
	s = { locked = { narHash = "h1", rev = "ssssssssss" }, original = { type = "github", owner = "o", repo = "s", host = "git.example.org" } },
})
local new = lock({
	root = { inputs = { a = "a", ignored = "i", follows = { "a" }, tar = "t", private = "p", self = "s" } },
	a = { locked = { narHash = "h2", rev = "bbbbbbbbbb", lastModified = 200 }, original = { type = "github", owner = "o", repo = "r", ref = "main" } },
	i = { locked = { narHash = "h2", rev = "jjjjjjjjjj" }, original = { type = "github", owner = "o", repo = "i" } },
	t = { locked = { narHash = "h2", url = "https://releases.nixos.org/nixos/unstable/nixos-2.b/nixexprs.tar.zst" }, original = { type = "tarball", url = "https://channels.nixos.org/x" } },
	p = { locked = { narHash = "h2", rev = "qqqqqqqqqq" }, original = { type = "git", url = "https://token123@git.example.org/r.git" } },
	s = { locked = { narHash = "h2", rev = "tttttttttt" }, original = { type = "github", owner = "o", repo = "s", host = "git.example.org" } },
})
local inputs = diff.inputs(old, new, { "ignored" })
local byName = {}
for _, row in ipairs(inputs) do
	byName[row.name] = row
end
check("input count (ignored, follows out)", #inputs, 4)
check("input revs", byName.a.oldRev .. ">" .. byName.a.newRev, "aaaaaaa>bbbbbbb")
check("input source", byName.a.source, "github:o/r/main")
check("input compare", byName.a.url, "https://github.com/o/r/compare/aaaaaaaaaa...bbbbbbbbbb")
check("tarball release name", byName.tar.newRev, "nixos-2.b")
check("tarball no compare", byName.tar.url, nil)
check("credentials stripped", byName.private.source, "https://git.example.org/r.git")
check("self-hosted compare", byName.self.url, "https://git.example.org/o/s/compare/ssssssssss...tttttttttt")
local hostile = lock({
	root = { inputs = { x = "x" } },
	x = { locked = { narHash = "h2", rev = "b;id" }, original = { type = "github", owner = "o$(id)", repo = "r" } },
})
local baseline = lock({
	root = { inputs = { x = "x" } },
	x = { locked = { narHash = "h1", rev = "a" }, original = { type = "github", owner = "o", repo = "r" } },
})
check("hostile lock gets no link", diff.inputs(baseline, hostile, {})[1].url, nil)
check("no lock", diff.inputs(nil, new, {}), nil)
check("same lock", #diff.inputs(old, old, {}), 0)

-- flatpak
local installed = "system\tcom.bambulab.BambuStudio\tstable\t2.8\tBambu Studio\tflathub\n"
	.. "system\torg.gnome.Platform\t50\t\tGNOME Platform\tflathub\n"
	.. "user\tcom.other.App\tstable\t1\tOther\tcustom\n"
local updates = "system\tcom.bambulab.BambuStudio\tstable\t2.9\n"
	.. "system\torg.gnome.Platform\t50\t\n"
	.. "user\tcom.other.App\tstable\t2\n"
	.. "system\tcom.unknown.App\tstable\t3\n"
rows = diff.flatpak(installed, updates)
byName = {}
for _, row in ipairs(rows) do
	byName[row.app] = row
end
check("flatpak count", #rows, 4)
check("flatpak name", byName["com.bambulab.BambuStudio"].name, "Bambu Studio")
check("flatpak versions", byName["com.bambulab.BambuStudio"].old .. ">" .. byName["com.bambulab.BambuStudio"].new, "2.8>2.9")
check("flathub link", byName["com.bambulab.BambuStudio"].changes, "https://flathub.org/apps/com.bambulab.BambuStudio")
check("runtime no link", byName["org.gnome.Platform"].changes, nil)
check("runtime no version", byName["org.gnome.Platform"].new, "")
check("other remote no link", byName["com.other.App"].changes, nil)
check("not in list falls back to id", byName["com.unknown.App"].name, "com.unknown.App")
check("flatpak empty", #diff.flatpak("", ""), 0)

-- pendingCount: a list is absent while its check is off or unavailable
check("pending all", diff.pendingCount({ packages = { 1, 2 }, flatpak = { 1 }, inputs = { 1 } }), 4)
check("pending without packages", diff.pendingCount({ flatpak = { 1 }, inputs = { 1, 2 } }), 3)
check("pending without flatpak", diff.pendingCount({ packages = {}, inputs = { 1 } }), 1)
check("pending only inputs", diff.pendingCount({ inputs = { 1 } }), 1)
check("pending nothing", diff.pendingCount({}), 0)

print(failed == 0 and "all tests passed" or (tostring(failed) .. " failed"))
