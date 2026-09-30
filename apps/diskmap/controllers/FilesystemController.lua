local ns = require("AppKit")
local Template = require("ui.template")
local Filesystem = require("apps.diskmap.models.Filesystem")
local Controller = {}; Controller.__index = Controller

-- `open(id)` shows a catalog resource in Diskmap.
function Controller.new(model, service, open)
	return setmetatable({model = model, service = service, open = open}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Filesystem.etlua", ns)
	self:update(state)
	return self.refs
end

-- Measures the locations no scan resource covers, once per scan: Inventory
-- clears `model.folderSizes` when a new scan begins.
function Controller:measure()
	if self.model.folderSizes or self.measuring or not self.service.measure then return end
	local paths = Filesystem.pending(self.model)
	self.measuring = true
	self.service.measure(paths, function(sizes, states)
		self.measuring = false
		local found = {}
		for index, path in ipairs(paths) do
			found[path] = {bytes = sizes[index] or 0, state = states and states[index] or "measured"}
		end
		self.model.folderSizes = found
		if self.template then self:render() end
	end)
end

-- A new scan clears the page's sizes, so each update measures again when
-- they are gone; otherwise rows would wait on sizes nobody is taking.
function Controller:update(state)
	if not self.template then return end
	self.state = state
	self:measure()
	self:render()
end

function Controller:render()
	local state = self.state
	local data = Filesystem.presentation(self.model, self.model.folderSizes, state and state.fullDiskAccess, state and state.query)
	data.query = state and state.query or ""
	data.actions = {}
	for _, area in ipairs(data.areas) do
		for index, row in ipairs(area.rows) do
			local key = area.id .. "_" .. index
			data.actions["reveal_" .. key] = function() self.service.reveal(row.path) end
			if row.resource then data.actions["open_" .. key] = function() self.open(row.resource) end end
		end
	end
	local _, refs = self.template:update(data)
	self.refs = refs
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs, self.state = nil, nil, nil
end

return Controller
