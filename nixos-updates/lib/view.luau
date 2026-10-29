--!nonstrict
-- Formatting shared by the compact panel and the details window.

local M = {}

M.RESULT_KEY = "nixos_updates"
M.COMMAND_KEY = "nixos_updates_command"
M.DETAILS_ID = "dmopp/nixos-updates:details"

function M.send(action)
	noctalia.state.set(M.COMMAND_KEY, { action = action, nonce = tostring(noctalia.nowMs()) })
end

function M.date(unixSeconds)
	if (tonumber(unixSeconds) or 0) <= 0 then
		return ""
	end
	return noctalia.formatTime("{:%Y-%m-%d}", unixSeconds)
end

function M.clock(unixSeconds)
	if os.time() - unixSeconds >= 20 * 3600 then
		return noctalia.formatTime("{:%Y-%m-%d %H:%M}", unixSeconds)
	end
	return noctalia.formatTime(noctalia.timeFormat(), unixSeconds)
end

-- "1.2.3 → 1.2.4"; added and removed entries say so instead of an empty side.
function M.change(old, new)
	if old == "" then
		return noctalia.tr("panel.added", { version = new })
	elseif new == "" then
		return noctalia.tr("panel.removed", { version = old })
	end
	return old .. "  →  " .. new
end

local function numbers(version)
	local out = {}
	for n in tostring(version):gmatch("%d+") do
		table.insert(out, tonumber(n))
	end
	return out
end

local function split(list)
	local set = {}
	for v in tostring(list):gmatch("[^,%s]+") do
		set[v] = true
	end
	return set
end

-- Kind of a package change for the details column: major, minor or patch
-- from the first numeric component that differs, a downgrade, or the versions
-- that disappear or appear when a package is installed in several versions.
function M.changeKind(old, new)
	if old == "" then
		return noctalia.tr("details.added")
	elseif new == "" then
		return noctalia.tr("details.removed")
	end
	if old:find(",", 1, true) or new:find(",", 1, true) then
		local before, after = split(old), split(new)
		local gone, added = {}, {}
		for v in pairs(before) do
			if not after[v] then
				table.insert(gone, v)
			end
		end
		for v in pairs(after) do
			if not before[v] then
				table.insert(added, v)
			end
		end
		table.sort(gone)
		table.sort(added)
		local parts = {}
		if #added > 0 then
			table.insert(parts, noctalia.tr("details.versions_added", { versions = table.concat(added, ", ") }))
		end
		if #gone > 0 then
			table.insert(parts, noctalia.tr("details.versions_removed", { versions = table.concat(gone, ", ") }))
		end
		return table.concat(parts, " · ")
	end
	local a, b = numbers(old), numbers(new)
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x ~= y then
			if y < x then
				return noctalia.tr("details.downgrade")
			end
			return noctalia.tr(i == 1 and "details.major" or i == 2 and "details.minor" or "details.patch")
		end
	end
	return noctalia.tr("details.other")
end

function M.flatpakChange(fp)
	if fp.new == "" then
		return noctalia.tr("panel.new_commit")
	end
	return M.change(fp.old, fp.new)
end

-- One line under the title: running step, last check, or "never".
function M.status(result)
	if result.running then
		if result.step ~= nil and result.step ~= "" then
			return noctalia.tr("panel.checking_step", { step = noctalia.tr("steps." .. result.step) })
		end
		return noctalia.tr("panel.checking")
	elseif result.checkedAt == nil then
		return noctalia.tr("panel.never_checked")
	elseif (tonumber(result.count) or 0) == 0 then
		return noctalia.tr("panel.up_to_date", { time = M.clock(result.checkedAt) })
	end
	return noctalia.trp("panel.pending", result.count, { time = M.clock(result.checkedAt) })
end

function M.openCompare(input)
	if input.url ~= nil then
		noctalia.runAsync({ "xdg-open", input.url })
	end
end

-- Check now plus Update (or a shortcut to the settings when no update
-- command is set), for the bottom of both panels.
function M.actions(result, onUpdate)
	local buttons = {
		ui.button({
			text = noctalia.tr("panel.check_now"),
			glyph = "refresh",
			variant = "ghost",
			controlSize = "sm",
			enabled = not result.running,
			onClick = function()
				M.send("check")
			end,
		}),
		ui.box({ flexGrow = 1, height = 1, fill = "on_surface/0" }),
	}
	if result.hasUpdateCommand then
		table.insert(buttons, ui.button({
			text = noctalia.tr("panel.update"),
			glyph = "terminal",
			controlSize = "sm",
			onClick = function()
				M.send("update")
				onUpdate()
			end,
		}))
	else
		table.insert(buttons, ui.button({
			text = noctalia.tr("panel.set_update_command"),
			glyph = "settings",
			variant = "ghost",
			controlSize = "sm",
			onClick = function()
				noctalia.openSettings()
			end,
		}))
	end
	return buttons
end

return M
