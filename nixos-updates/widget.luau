--!nonstrict
-- Bar widget: glyph plus the number of pending updates (package changes,
-- Flatpak updates and flake inputs with new commits). Left-click opens the
-- panel through the manifest action.

local RESULT_KEY = "nixos_updates"

local result = noctalia.state.get(RESULT_KEY) or {}

local function config(key, fallback)
	local value = noctalia.getConfig(key)
	if value == nil then
		return fallback
	end
	return value
end

local function tooltip()
	local rows = {}
	if result.running then
		table.insert(rows, { key = noctalia.tr("widget.title"), value = noctalia.tr("panel.checking") })
	end
	for _, e in ipairs(result.errors or {}) do
		table.insert(rows, { key = noctalia.tr("widget.error"), value = e.message })
	end
	if result.checkedAt == nil then
		if #rows == 0 then
			table.insert(rows, { key = noctalia.tr("widget.title"), value = noctalia.tr("panel.never_checked") })
		end
		return rows
	end
	if type(result.packages) == "table" then
		table.insert(rows, { key = noctalia.tr("widget.packages"), value = tostring(#result.packages) })
	end
	if type(result.inputs) == "table" then
		table.insert(rows, { key = noctalia.tr("widget.inputs"), value = tostring(#result.inputs) })
	end
	if type(result.flatpak) == "table" then
		table.insert(rows, { key = noctalia.tr("widget.flatpak"), value = tostring(#result.flatpak) })
	end
	table.insert(rows, {
		key = noctalia.tr("widget.checked"),
		value = noctalia.formatTime("{:%Y-%m-%d %H:%M}", result.checkedAt),
	})
	return rows
end

local function render()
	local n = tonumber(result.count) or 0
	local hasErrors = #(result.errors or {}) > 0
	barWidget.setVisible(n > 0 or hasErrors or result.running or config("hide_when_up_to_date", false) ~= true)

	local glyph = tostring(config("glyph", "package"))
	barWidget.setGlyph(glyph ~= "" and glyph or "package")
	if n > 0 then
		barWidget.setGlyphColor(config("highlight_color", "primary"))
	elseif hasErrors then
		barWidget.setGlyphColor("error")
	else
		barWidget.setGlyphColor("on_surface")
	end

	local text = ""
	if config("show_count", true) == true and (n > 0 or config("show_zero", false) == true) then
		text = tostring(n)
	end
	barWidget.setText(text)
	barWidget.setTooltip(tooltip())
end

noctalia.state.watch(RESULT_KEY, function(value)
	if type(value) == "table" then
		result = value
		render()
	end
end)

render()
