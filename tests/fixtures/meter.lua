-- The views of one Diskmap size meter (apps/diskmap/views/cells/Meter.etlua),
-- found in its table cell by class. `value` and `share` are the labels the
-- row shows; frames compare in window coordinates (`view.frameInWindow`).
return function(cell)
	cell:layout()
	local meter = { cell = cell }
	local labels = {}
	local function visit(view)
		local class = view.className
		if class == "LuaLevelIndicator" then meter.bar = view
		elseif class == "LuaProgressIndicator" then meter.spinner = view
		elseif class == "LuaSymbolImageView" then meter.symbol = view
		elseif class == "LuaLabel" and not view.hidden then table.insert(labels, view) end
		for _, child in ipairs(view.subviews) do visit(child) end
	end
	visit(cell)
	meter.value, meter.share = labels[1], labels[2]
	return meter
end
