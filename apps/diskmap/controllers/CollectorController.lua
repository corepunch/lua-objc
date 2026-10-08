local Model = require("data.model")
local ns = require("AppKit")
local Locations = require("apps.diskmap.models.Locations")
local Rows = require("apps.diskmap.flows.Rows")
local Collector = {}; Collector.__index = Collector

function Collector.new(app)
	local self = setmetatable({app = app}, Collector)
	self.rows = Rows(self)
	return self
end

function Collector:update()
	local refs = self.refs
	if not refs then return end
	local count = self.app.basket:count()
	refs.collectorText.text = count == 0 and "Drag items here to mark them for cleanup" or self.app.basket:summary()
	refs.collectorReview.enabled = count > 0
	refs.collectorArea.hidden = self:hidden()
end

-- The staging area shows while items wait or a drag is over the window, and
-- not on the basket page, which lists the same items itself.
function Collector:hidden()
	if self.dragging then return false end
	return self.app.basket:count() == 0 or self.onBasket == true
end

-- A file drag reveals the empty staging area. Delay an exit to the next
-- run-loop turn: AppKit exits the parent before entering its child target.
function Collector:drag(target, targeted)
	self.dragTargets = self.dragTargets or {}
	self.dragTargets[target] = targeted or nil
	self.dragGeneration = (self.dragGeneration or 0) + 1
	local generation = self.dragGeneration
	if targeted then self:dragged(generation)
	else ns.async(function() ns.sleep(0); self:dragged(generation) end) end
end
function Collector:dragged(generation)
	if self.closed or generation ~= self.dragGeneration then return end
	self.dragging = next(self.dragTargets) ~= nil
	if self.refs then self.refs.collectorArea.hidden = self:hidden() end
end

-- Files dropped on the collector are marked for cleanup. A catalog location
-- keeps its cleanup rules; any other file or folder is measured first and
-- then validated like everything else in the basket.
function Collector:dropToMark(paths)
	local refused, pending, accepted = {}, {}, 0
	for _, path in ipairs(paths) do
		local resource = Locations:findPath(path)
		local item
		if resource and self.rows:markableResource(resource) then
			local measured = resource:measurement()
			item = {path = path, name = resource.name, bytes = measured and measured.bytes, resourceId = resource.id,
				source = "Dropped", consequence = resource.advice}
		else
			item = {path = path, name = path:match("([^/]+)$") or path, source = "Dropped"}
			table.insert(pending, item)
		end
		if self.app.basket:isMarked(path) then
			accepted = accepted + 1
		else
			local ok, reason = self.app.basket:toggle(item)
			if ok then accepted = accepted + 1 else table.insert(refused, (item.name or path) .. ": " .. tostring(reason)) end
		end
	end
	if #refused > 0 then self.app.service.showError("Some items were not marked", table.concat(refused, "\n")) end
	local measure = self.app.service.measure
	local scan = self.app.model.scan
	if #pending > 0 then
		local list = {}
		for _, item in ipairs(pending) do table.insert(list, item.path) end
		measure(list, function(sizes)
			if self.closed or self.app.model.scan ~= scan then return end
			for index, item in ipairs(pending) do item.bytes = sizes[index] end
			self.app.basketChanged()
		end)
	end
	return accepted > 0
end

function Collector:dispose() self.closed, self.refs = true, nil end

-- Collector actions are entry points into their window, including deferred
-- drag exits. Bind that window's store before reading its basket.
for name, method in pairs(Collector) do
	if type(method) == "function" and name ~= "new" then
		Collector[name] = function(self, ...)
			Model.bind(self.app.model)
			return method(self, ...)
		end
	end
end

return Collector
