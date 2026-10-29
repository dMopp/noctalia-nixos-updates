--!nonstrict
-- Panel: pending updates like `apt list --upgradable` - changed flake inputs
-- with their revisions, the package versions that change with them, and
-- Flatpak updates - plus buttons to check again and to run the update command.
-- Each section shows its first PREVIEW rows; the details window has them all.

local view = require("./lib/view.luau")

local PREVIEW = 6

local result = noctalia.state.get(view.RESULT_KEY) or {}
local expanded = { inputs = true, packages = true, flatpak = true }

local function openDetails()
	panel.close()
	noctalia.togglePanel(view.DETAILS_ID)
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
	if view.date(input.oldDate) ~= "" and view.date(input.newDate) ~= "" then
		dates = view.date(input.oldDate) .. "  →  " .. view.date(input.newDate)
	end
	local onClick = nil
	local tooltip = nil
	if input.url ~= nil then
		onClick = function()
			view.openCompare(input)
		end
		tooltip = noctalia.tr("panel.open_compare")
	end
	return row("input-" .. input.name, input.name, meta, dates, onClick, tooltip)
end

local function packageRow(pkg)
	return row("pkg-" .. pkg.name, pkg.name, "", view.change(pkg.old, pkg.new))
end

local function flatpakRow(fp)
	local meta = fp.app .. " · " .. fp.branch .. " · " .. fp.installation
	return row("fp-" .. fp.installation .. fp.app .. fp.branch, fp.name, meta, view.flatpakChange(fp))
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
		for i = 1, math.min(#rows, PREVIEW) do
			table.insert(list, makeRow(rows[i]))
		end
		if #rows > PREVIEW then
			table.insert(list, ui.button({
				text = noctalia.tr("panel.more", { count = #rows - PREVIEW }),
				glyph = "list-details",
				fontSize = 12,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				contentAlign = "start",
				onClick = openDetails,
			}))
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
	table.insert(body, ui.label({ text = view.status(result), fontSize = 12, color = "on_surface_variant" }))

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

	panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.glyph({ name = "snowflake", size = 20, color = "primary" }),
			ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
			ui.button({ glyph = "arrows-maximize", variant = "ghost", tooltip = noctalia.tr("panel.open_details"), onClick = openDetails }),
			ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
		}),
		ui.scroll({ flexGrow = 1, gap = 10 }, body),
		ui.row({ align = "center", gap = 8 }, view.actions(result, function()
			panel.close()
		end)),
	}))
end

noctalia.state.watch(view.RESULT_KEY, function(value)
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
