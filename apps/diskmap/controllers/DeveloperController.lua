local ns = require("AppKit")
local Template = require("ui.template")
local Developer = require("apps.diskmap.models.Developer")
local Controller = {}; Controller.__index = Controller

-- `handlers.open(id)` opens a category sheet; `handlers.simulators()` and
-- `handlers.sdks(row)` open the dedicated device and SDK sheets.
function Controller.new(model, handlers)
	return setmetatable({model = model, handlers = handlers}, Controller)
end

function Controller:mount(host)
	self.template = Template.new(host, "apps/diskmap/views/Developer.etlua", ns)
	self:update()
	return self.refs
end

function Controller:activate(tile)
	if tile.open == "simulators" then self.handlers.simulators()
	elseif tile.open == "sdks" then self.handlers.sdks(self.model.resources:find(tile.id))
	else self.handlers.open(tile.open) end
end

function Controller:update()
	if not self.template then return end
	local data = Developer.presentation(self.model)
	data.actions = {showAll = function() self.handlers.open("developer") end}
	for _, tile in ipairs(data.tiles) do
		data.actions["tile_" .. tile.id] = function() self:activate(tile) end
	end
	local _, refs = self.template:update(data)
	self.refs = refs
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
