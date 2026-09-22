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
	local rows, actions = self:rows(nil, 5), {}
	for _, row in ipairs(rows) do actions["review_" .. row.id] = function() self.review(row.id) end end
	return {suggestions = rows, actions = actions}
end
function Controller:toggleKeep(id)
	if not Preferences.toggle(self.model, id) then return false end
	local saved = not self.service.saveKeep or self.service.saveKeep(self.model.kept)
	local message; if not saved then message = "Keep preference could not be saved." end
	self.changed(message)
	return saved
end
return Controller
