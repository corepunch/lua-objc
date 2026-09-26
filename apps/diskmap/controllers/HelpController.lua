local ns = require("AppKit")
local Template = require("ui.template")
local Help = require("apps.diskmap.models.Help")
local Controller = {}; Controller.__index = Controller

-- `open(target)` follows a topic's button: a page id or a menu command.
-- `shortcuts()` lists the menu bar's shortcuts and `links` titles the
-- buttons, so both come from the command layer rather than the help text.
function Controller.new(open, shortcuts, links)
	return setmetatable({open = open, shortcuts = shortcuts, links = links}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Help.etlua", ns)
	self.query = nil
	self:update(state)
	return self.refs
end

-- Like the Storage Guide, help re-renders only when its search changes, so
-- scan progress never collapses the topic being read.
function Controller:update(state)
	if not self.template or (self.refs and self.query == state.query) then return end
	self.query = state.query
	local data = Help.presentation(state.query, self.shortcuts(), self.links)
	data.query = state.query or ""
	data.expandAll = (state.query or "") ~= ""
	data.actions = {}
	for _, chapter in ipairs(data.chapters) do
		for _, topic in ipairs(chapter.topics) do
			if topic.link then data.actions["open_" .. topic.id] = function() self.open(topic.target) end end
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
