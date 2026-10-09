-- Page-level and selection operations feed the native window toolbar.
-- Inline flags and navigation links remain with their individual rows.
local Operations = {}
function Operations.forPage(id, data)
	local items, seen = {}, {}
	local function add(key, title, symbol, action, disabled)
		if seen[key] then return end
		seen[key] = true
		table.insert(items, {id = key, title = (data.texts or {})[key] or title, icon = symbol, action = action or key,
			disabled = disabled == true or (data.disabled or {})[key] == true, hidden = (data.hidden or {})[key] == true})
	end
	local layout = data.layout or {}
	for _, button in ipairs(layout.buttons or {}) do add(button.id, button.title, button.systemImage or "ellipsis.circle", button.action, button.disabled) end
	for _, section in ipairs(layout.sections or {}) do
		for _, button in ipairs(section.buttons or {}) do add(button.id, button.title, button.systemImage or "flag", button.action, button.disabled) end
	end
	-- The breakdown pages act on their rows and charts in place: a row opens
	-- with a double-click and flags with its own button.
	if id == "basket" then
		add("history", "Action History", "clock")
		add("inspect", "Open Contents", "folder")
		add("reveal", "Show in Finder", "arrow.up.forward.square")
		add("remove", "Remove Flag", "flag.slash")
		add("clear", "Clear All Flags", "flag.slash.fill")
		add("emptyTrash", "Empty Trash…", "trash.fill")
		add("trash", "Move to Trash", "trash")
	elseif id == "worktrees" then
		add("retry", "Refresh Worktrees", "arrow.clockwise")
		add("reveal", "Show in Finder", "arrow.up.forward.square")
		add("keep", "Keep", "pin")
		add("openOwner", "Open Owner…", "arrow.up.forward.square")
		add("prune", "Prune Missing…", "scissors")
	elseif id == "simulators" then
		add("planKeepThis", "Keep This Device", "iphone")
		add("planPreserve", data.plan and data.plan.preserveTitle or "Keep Device", "pin")
		add("retry", "Refresh Simulators", "arrow.clockwise")
		add("components", "Xcode Components…", "shippingbox")
		add("reveal", "Show in Finder", "arrow.up.forward.square")
		add("erase", "Erase Device…", "eraser")
		add("delete", "Delete Device…", "trash")
		add("deleteUnavailable", "Delete Unavailable Devices…", "trash", "unavailable")
		add("deleteRuntime", "Delete Runtime…", "trash.circle")
	elseif id == "updates" then
		add("openSoftwareUpdate", "Software Update…", "gearshape")
		add("openTimeMachine", "Time Machine Settings…", "clock.arrow.circlepath")
	elseif id == "overview" and not data.accessHidden then
		add("access", data.accessTitle or "Scan Access…", "lock.shield", nil, data.accessHidden)
	end
	return items
end
return Operations
