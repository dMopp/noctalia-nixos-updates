--!nonstrict
-- Panel: pending updates like `apt list --upgradable` - changed flake inputs
-- with their revisions, the package versions that change with them, and
-- Flatpak updates - plus buttons to check again and to run the update command.

local RESULT_KEY = "nixos_updates"
local COMMAND_KEY = "nixos_updates_command"

local result = noctalia.state.get(RESULT_KEY) or {}
local expanded = { inputs = true, packages = true, flatpak = true }

local function send(action)
	noctalia.state.set(COMMAND_KEY, { action = action, nonce = tostring(noctalia.nowMs()) })
end

local function date(unixSeconds)
	if (tonumber(unixSeconds) or 0) <= 0 then
		return ""
	end
	return noctalia.formatTime("{:%Y-%m-%d}", unixSeconds)
end

local function clock(unixSeconds)
	if os.time() - unixSeconds >= 20 * 3600 then
		return noctalia.formatTime("{:%Y-%m-%d %H:%M}", unixSeconds)
	end
	return noctalia.formatTime(noctalia.timeFormat(), unixSeconds)
end

-- "1.2.3 → 1.2.4"; added and removed entries say so instead of an empty side.
local function change(old, new)
	if old == "" then
		return noctalia.tr("panel.added", { version = new })
	elseif new == "" then
		return noctalia.tr("panel.removed", { version = old })
	end
	return old .. "  →  " .. new
end

local function row(key, title, meta, right, onClick, tooltip)
	return ui.row({
		key = key,
		align = "center",
		gap = 10,
		paddingH = 8,
		paddingV = 5,
		radius = 8,
		tooltip = tooltip,
		onClick = onClick,
	}, {
		ui.column({ flexGrow = 1, gap = 1 }, {
			ui.label({ text = title, fontSize = 13, fontWeight = "medium", color = "on_surface", maxLines = 1 }),
			meta ~= "" and ui.label({ text = meta, fontSize = 11, color = "on_surface_variant", maxLines = 1 }) or nil,
		}),
		right ~= "" and ui.label({ text = right, fontSize = 12, color = "on_surface", textAlign = "end", maxLines = 1 }) or nil,
	})
end

-- Name on its own line, revisions and source below, dates on the right.
local function inputRow(input)
	local meta = input.oldRev .. "  →  " .. input.newRev
	if input.source ~= "" then
		meta = meta .. "  ·  " .. input.source
	end
	local dates = ""
	if date(input.oldDate) ~= "" and date(input.newDate) ~= "" then
		dates = date(input.oldDate) .. "  →  " .. date(input.newDate)
	end
	local onClick = nil
	local tooltip = nil
	if input.url ~= nil then
		onClick = function()
			noctalia.runAsync({ "xdg-open", input.url })
		end
		tooltip = noctalia.tr("panel.open_compare")
	end
	return row("input-" .. input.name, input.name, meta, dates, onClick, tooltip)
end

local function packageRow(pkg)
	return row("pkg-" .. pkg.name, pkg.name, "", change(pkg.old, pkg.new))
end

local function flatpakRow(fp)
	local meta = fp.app .. " · " .. fp.branch .. " · " .. fp.installation
	local right = change(fp.old, fp.new)
	if fp.new == "" then
		right = noctalia.tr("panel.new_commit")
	end
	return row("fp-" .. fp.installation .. fp.app .. fp.branch, fp.name, meta, right)
end

-- Collapsible section; nil when the check did not cover it.
local function section(id, glyph, labelKey, rows, makeRow)
	if type(rows) ~= "table" then
		return nil
	end
	local open = expanded[id] and #rows > 0
	local children = {
		ui.row({ align = "center", gap = 6 }, {
			ui.glyph({ name = glyph, size = 16, color = "primary" }),
			ui.button({
				text = noctalia.tr(labelKey, { count = #rows }),
				glyph = #rows == 0 and "check" or (open and "chevron-up" or "chevron-down"),
				fontSize = 12,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				contentAlign = "start",
				onClick = function()
					expanded[id] = not expanded[id]
					render()
				end,
			}),
		}),
	}
	if open then
		local list = {}
		for _, item in ipairs(rows) do
			table.insert(list, makeRow(item))
		end
		table.insert(children, ui.column({ gap = 2 }, list))
	end
	return ui.column({ gap = 4 }, children)
end

function render()
	local body = {}
	for _, e in ipairs(result.errors or {}) do
		table.insert(body, ui.label({ text = e.message, fontSize = 12, color = "error", maxLines = 4 }))
	end

	local status
	if result.running then
		local stepKey = result.step ~= nil and result.step ~= "" and ("steps." .. result.step) or nil
		status = stepKey and noctalia.tr("panel.checking_step", { step = noctalia.tr(stepKey) }) or noctalia.tr("panel.checking")
	elseif result.checkedAt == nil then
		status = noctalia.tr("panel.never_checked")
	elseif (tonumber(result.count) or 0) == 0 then
		status = noctalia.tr("panel.up_to_date", { time = clock(result.checkedAt) })
	else
		status = noctalia.trp("panel.pending", result.count, { time = clock(result.checkedAt) })
	end
	table.insert(body, ui.label({ text = status, fontSize = 12, color = "on_surface_variant" }))

	if result.checkedAt ~= nil then
		local sections = {
			section("inputs", "snowflake", "panel.inputs", result.inputs, inputRow),
			section("packages", "package", "panel.packages", result.packages, packageRow),
			section("flatpak", "box", "panel.flatpak", result.flatpak, flatpakRow),
		}
		for i = 1, 3 do
			if sections[i] ~= nil then
				table.insert(body, sections[i])
			end
		end
		if type(result.inputs) == "table" and type(result.packages) ~= "table" and #result.inputs > 0 then
			table.insert(body, ui.label({ text = noctalia.tr("panel.no_package_list"), fontSize = 11, color = "on_surface_variant", maxLines = 3 }))
		end
	end

	local footer = {
		ui.button({
			text = noctalia.tr("panel.check_now"),
			glyph = "refresh",
			variant = "ghost",
			controlSize = "sm",
			enabled = not result.running,
			onClick = function()
				send("check")
			end,
		}),
		ui.box({ flexGrow = 1, height = 1, fill = "on_surface/0" }),
	}
	if result.hasUpdateCommand then
		table.insert(footer, ui.button({
			text = noctalia.tr("panel.update"),
			glyph = "terminal",
			controlSize = "sm",
			onClick = function()
				send("update")
				panel.close()
			end,
		}))
	else
		table.insert(footer, ui.button({
			text = noctalia.tr("panel.set_update_command"),
			glyph = "settings",
			variant = "ghost",
			controlSize = "sm",
			onClick = function()
				noctalia.openSettings()
			end,
		}))
	end

	panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.glyph({ name = "snowflake", size = 20, color = "primary" }),
			ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
			ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
		}),
		ui.scroll({ flexGrow = 1, gap = 10 }, body),
		ui.row({ align = "center", gap = 8 }, footer),
	}))
end

noctalia.state.watch(RESULT_KEY, function(value)
	if type(value) == "table" then
		result = value
		render()
	end
end)

function onOpen(_context)
	render()
end

function onCloseClicked()
	panel.close()
end

render()
