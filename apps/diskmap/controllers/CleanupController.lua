local Cleanup = require("apps.diskmap.models.Cleanup")
local Preferences = require("apps.diskmap.models.Preferences")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service, review, changed)
	return setmetatable({model = model, service = service, review = review, changed = changed or function() end}, Controller)
end
function Controller:rows(query, limit)
	local rows, needle = {}, (query or ""):lower()
	for _, row in ipairs(Cleanup.suggestions(self.model)) do
		if (row.name .. " " .. row.subtitle):lower():find(needle, 1, true) then
			rows[#rows + 1] = row
			if limit and #rows >= limit then break end
		end
	end
	return rows
end
function Controller:presentation()
	local rows, actions = self:rows(), {}
	for _, row in ipairs(rows) do actions["review_" .. row.id] = function() self.review(row.id) end end
	local groups = {{name = "Safe/rebuildable", rows = {}}, {name = "Needs review", rows = {}}, {name = "Essential to keep", rows = {}}}
	for _, row in ipairs(rows) do
		local group = row.impact == "Safe/rebuildable" and groups[1] or groups[2]
		group.rows[#group.rows + 1] = row
	end
	for _, row in ipairs(require("apps.diskmap.models.Categories").managementRows(self.model, "runtimes")) do
		if (row.bytes or 0) > 0 then
			row.icon = "iphone"; row.color = "systemBlue"; row.subtitle = "Keep installed runtimes required by your projects."
			groups[3].rows[#groups[3].rows + 1] = row
			actions["review_" .. row.id] = function() self.review("runtimes") end
		end
	end
	for index, group in ipairs(groups) do
		local bytes, partial = 0, false; for _, row in ipairs(group.rows) do bytes = bytes + (row.bytes or 0); partial = partial or row.partial end
		group.index = index; group.size = (partial and "≥ " or "") .. require("apps.diskmap.Model").size(bytes)
		actions["group_" .. index] = function() self.review(nil, group.name) end
	end
	return {suggestions = rows, groups = groups, actions = actions}
end
function Controller:toggleKeep(id)
	if not Preferences.toggle(self.model, id) then return false end
	local saved = not self.service.saveKeep or self.service.saveKeep(self.model.kept)
	local message; if not saved then message = "Keep preference could not be saved." end
	self.changed(message)
	return saved
end
return Controller
