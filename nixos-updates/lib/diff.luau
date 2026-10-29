--!nonstrict
-- Pure comparisons for the service: flake inputs between two lock files,
-- package versions between two evaluations, Flatpak updates from the TSV
-- files check.sh writes.

local M = {}

local function shortRev(locked)
	if type(locked) ~= "table" then
		return ""
	end
	if type(locked.rev) == "string" then
		return locked.rev:sub(1, 7)
	end
	-- Tarball inputs (channels) have no rev; their URL names the release.
	if type(locked.url) == "string" then
		return locked.url:match("([^/]+)/[^/]*$") or ""
	end
	return ""
end

local function source(original)
	if type(original) ~= "table" then
		return ""
	end
	if original.owner ~= nil and original.repo ~= nil then
		local ref = original.ref ~= nil and ("/" .. original.ref) or ""
		return tostring(original.type) .. ":" .. original.owner .. "/" .. original.repo .. ref
	end
	return tostring(original.url or original.path or original.type or "")
end

-- Web page with the commits between two revisions, where the host has one.
local function compareUrl(original, oldLocked, newLocked)
	if type(original) ~= "table" or type(oldLocked) ~= "table" or type(newLocked) ~= "table" then
		return nil
	end
	if oldLocked.rev == nil or newLocked.rev == nil or original.owner == nil or original.repo == nil then
		return nil
	end
	local hosts = { github = "https://github.com", gitlab = "https://gitlab.com", codeberg = "https://codeberg.org" }
	local base = hosts[original.type]
	if base == nil then
		return nil
	end
	local sep = original.type == "gitlab" and "/-/compare/" or "/compare/"
	return base .. "/" .. original.owner .. "/" .. original.repo .. sep .. oldLocked.rev .. "..." .. newLocked.rev
end

local function rootInputs(lock)
	if type(lock) ~= "table" or type(lock.nodes) ~= "table" then
		return nil
	end
	local root = lock.nodes[lock.root or "root"]
	if type(root) ~= "table" then
		return nil
	end
	return root.inputs or {}
end

-- Direct inputs of the flake whose locked content differs. Inputs that follow
-- another one (lists in the lock) are left out, they show up under that one.
function M.inputs(oldLock, newLock, ignored)
	local oldInputs = rootInputs(oldLock)
	local newInputs = rootInputs(newLock)
	if oldInputs == nil or newInputs == nil then
		return nil
	end
	local skip = {}
	for _, name in ipairs(ignored or {}) do
		skip[noctalia.string.trim(tostring(name))] = true
	end
	local rows = {}
	local total = 0
	for name, oldKey in pairs(oldInputs) do
		local newKey = newInputs[name]
		if type(oldKey) == "string" and type(newKey) == "string" then
			total += 1
			local old = oldLock.nodes[oldKey] or {}
			local new = newLock.nodes[newKey] or {}
			local oldHash = old.locked and old.locked.narHash
			local newHash = new.locked and new.locked.narHash
			if not skip[name] and oldHash ~= newHash then
				table.insert(rows, {
					name = name,
					source = source(new.original or old.original),
					oldRev = shortRev(old.locked),
					newRev = shortRev(new.locked),
					oldDate = tonumber(old.locked and old.locked.lastModified) or 0,
					newDate = tonumber(new.locked and new.locked.lastModified) or 0,
					url = compareUrl(new.original or old.original, old.locked, new.locked),
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return rows, total
end

local function versions(list)
	local byName = {}
	for _, entry in ipairs(type(list) == "table" and list or {}) do
		local name = tostring(entry.n or "")
		if name ~= "" then
			byName[name] = byName[name] or {}
			byName[name][tostring(entry.v or "")] = true
		end
	end
	local out = {}
	for name, set in pairs(byName) do
		local list2 = {}
		for v in pairs(set) do
			table.insert(list2, v)
		end
		table.sort(list2)
		out[name] = table.concat(list2, ", ")
	end
	return out
end

-- Packages whose version changes, appears or disappears. old/new are "" for
-- added/removed ones.
function M.packages(oldList, newList)
	local old = versions(oldList)
	local new = versions(newList)
	local rows = {}
	local seen = {}
	for name, v in pairs(old) do
		seen[name] = true
		if new[name] ~= v then
			table.insert(rows, { name = name, old = v, new = new[name] or "" })
		end
	end
	for name, v in pairs(new) do
		if not seen[name] then
			table.insert(rows, { name = name, old = "", new = v })
		end
	end
	table.sort(rows, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return rows
end

local function tsv(text)
	local rows = {}
	for line in tostring(text or ""):gmatch("[^\n]+") do
		local fields = {}
		for field in (line .. "\t"):gmatch("([^\t]*)\t") do
			table.insert(fields, field)
		end
		table.insert(rows, fields)
	end
	return rows
end

-- installed: installation, application, branch, version, name.
-- updates: installation, application, branch, new version.
function M.flatpak(installedText, updatesText)
	local installed = {}
	for _, f in ipairs(tsv(installedText)) do
		installed[(f[1] or "") .. "|" .. (f[2] or "") .. "|" .. (f[3] or "")] = { version = f[4] or "", name = f[5] or "" }
	end
	local rows = {}
	for _, f in ipairs(tsv(updatesText)) do
		local app = f[2] or ""
		if app ~= "" then
			local have = installed[(f[1] or "") .. "|" .. app .. "|" .. (f[3] or "")] or {}
			table.insert(rows, {
				installation = f[1] or "",
				app = app,
				branch = f[3] or "",
				name = (have.name ~= nil and have.name ~= "") and have.name or app,
				old = have.version or "",
				new = f[4] or "",
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return rows
end

return M
