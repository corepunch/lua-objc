local ns = require("AppKit")
local Template = require("ui.template")
local Guide = require("apps.diskmap.models.Guide")
local Controller = {}; Controller.__index = Controller

-- `open(destination)` shows a topic's storage in Diskmap: a category id or
-- the simulator device sheet.
function Controller.new(model, open)
	return setmetatable({model = model, open = open}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Guide.etlua", ns)
	self.query = nil
	self:update(state)
	return self.refs
end

-- The guide re-renders only when its search changes. Scan progress would
-- otherwise rebuild every topic and collapse the one being read; sizes
-- refresh the next time the page opens.
function Controller:update(state)
	if not self.template or (self.refs and self.query == state.query) then return end
	self.query = state.query
	local data = Guide.presentation(self.model, state.query)
	data.query = state.query or ""
	data.expandAll = (state.query or "") ~= ""
	data.actions = {}
	for _, chapter in ipairs(data.chapters) do
		for _, topic in ipairs(chapter.topics) do
			if topic.open then data.actions["open_" .. topic.id] = function() self.open(topic.open) end end
		end
	end
	local _, refs = self.template:update(data)
	self.refs = refs
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs, self.query = nil, nil, nil
end

return Controller
