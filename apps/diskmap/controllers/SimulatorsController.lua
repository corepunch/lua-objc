local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Simulators = require("apps.diskmap.models.Simulators")
local Controller = {}; Controller.__index = Controller

-- The Simulators page: devices from CoreSimulator's folders and runtimes from
-- `simctl runtime list`. `changed` asks the root to remeasure after an action.
function Controller.new(model, service, changed)
	return setmetatable({model = model, service = service, changed = changed, generation = 0,
		inventory = {}, runtimes = {}, runtimeList = nil, query = "", filterIndex = 1}, Controller)
end

function Controller:mount(host, state)
	self.generation = self.generation + 1
	self.query, self.filterIndex, self.selected, self.selectedRuntime = state.query or "", 1, nil, nil
	self.template = Template.new(host, "apps/diskmap/views/Simulators.etlua", ns)
	local _, refs = self.template:update({filters = Simulators.filters, actions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:show() end,
		select = function(_, _, row) self.selected = row; self:buttons() end,
		selectRuntime = function(_, _, row) self.selectedRuntime = row; self:buttons() end,
		reveal = function() if self.selected and self.selected.path then self.service.reveal(self.selected.path) end end,
		erase = function() self:perform("erase") end,
		delete = function() self:perform("delete") end,
		unavailable = function() self:perform("delete", true) end,
		deleteRuntime = function() self:deleteRuntime() end,
		components = function() self.service.openOwner("xcode") end,
	}})
	self.refs = refs
	self:load()
	return refs
end

function Controller:filter() return Simulators.filters[self.filterIndex] end

function Controller:buttons()
	local refs = self.refs
	if not refs then return end
	local allowed = not self.busy
	refs.erase.enabled = allowed and Simulators.command("erase", self.selected, self.model) ~= nil
	refs.delete.enabled = allowed and Simulators.command("delete", self.selected, self.model) ~= nil
	refs.reveal.enabled = allowed and self.selected ~= nil and type(self.selected.path) == "string"
	local unavailable = 0
	for _, row in ipairs(Simulators.rows(self.inventory, nil, "Unavailable")) do
		if Simulators.command("delete", row, self.model) then unavailable = unavailable + 1 end
	end
	refs.unavailableTileAction.enabled = allowed and unavailable > 0
	refs.deleteRuntime.enabled = allowed and Simulators.runtimeCommand(self.selectedRuntime, self.model) ~= nil
	local _, reason = Simulators.validateRuntime(self.selectedRuntime, self.model)
	refs.runtimeStatus.text = self.selectedRuntime and reason and reason.message or ""
end

-- Presents the loaded inventory without reloading it: filters and search
-- change what is shown, never what is measured.
function Controller:show()
	local refs = self.refs
	if not refs then return end
	local rows = Simulators.rows(self.inventory, self.query, self:filter())
	refs.devices:replaceRows(rows)
	self.runtimes = Simulators.runtimeRows(self.runtimeList, self.inventory, self.query)
	refs.runtimes:replaceRows(self.runtimes)
	refs.runtimesSection.hidden = self.runtimeList ~= nil and #Simulators.runtimeRows(self.runtimeList, self.inventory) == 0
	local summary = Simulators.summary(self.inventory, Simulators.runtimeRows(self.runtimeList, self.inventory))
	refs.devicesTileValue.text = Model.size(summary.deviceBytes)
	refs.devicesTileDetail.text = summary.devices .. (summary.devices == 1 and " device" or " devices")
		.. (summary.stale > 0 and (" · " .. summary.stale .. " unused for " .. Simulators.staleDays .. " days") or "")
	refs.runtimesTileValue.text = self.runtimeList and Model.size(summary.runtimeBytes) or "Not measured"
	refs.runtimesTileDetail.text = self.runtimeList and (summary.runtimes .. (summary.runtimes == 1 and " runtime installed" or " runtimes installed"))
		or "simctl runtime list is unavailable"
	refs.unavailableTileValue.text = tostring(summary.unavailable)
	refs.unavailableTileDetail.text = summary.unavailable == 0 and "Every device has its runtime"
		or (Model.size(summary.unavailableBytes) .. " of apps and data on devices whose runtime is gone")
	refs.summary.text = self.busy and "Working…" or self.error
		or string.format("%s in %d devices and %s in %d runtimes", Model.size(summary.deviceBytes), summary.devices,
			self.runtimeList and Model.size(summary.runtimeBytes) or "unmeasured storage", summary.runtimes)
	refs.status.text = #rows == 0 and "No matching devices." or (#rows .. (#rows == 1 and " device" or " devices"))
	if self.busy then refs.devices:showLoading() else refs.devices:hideLoading() end
	self.selected, self.selectedRuntime = nil, nil
	self:buttons()
end

function Controller:update(state)
	if self.query == (state.query or "") then return end
	self.query = state.query or ""
	self:show()
end

function Controller:finish(generation, inventory, runtimeList)
	if generation ~= self.generation then return end
	self.busy = false
	if type(inventory) == "table" and type(inventory.devices) == "table" then self.inventory = inventory
	else self.error = "Simulator folders could not be read." end
	self.runtimeList = runtimeList
	self:show()
end

function Controller:load()
	if self.busy then return end
	self.busy = true; self.error = nil; self.inventory = {}; self:show()
	local generation = self.generation
	local runtimeList, inventory, pending = nil, nil, 2
	local function done()
		pending = pending - 1
		if pending == 0 then self:finish(generation, inventory, runtimeList) end
	end
	if type(self.service.simulatorRuntimes) == "function" then
		self.service.simulatorRuntimes(function(value) runtimeList = value; done() end)
	else done() end
	local ok, discovered = pcall(Simulators.discover, self.service, self.model.home)
	if not ok then done(); return end
	inventory = discovered
	local paths, slots = {}, {}
	for _, devices in pairs(discovered.devices or {}) do
		for _, device in ipairs(devices) do
			if device.dataPathSize == nil and device.measurePath then
				table.insert(paths, device.measurePath)
				table.insert(slots, device)
			end
		end
	end
	if #paths == 0 or type(self.service.measure) ~= "function" then done(); return end
	self.service.measure(paths, function(sizes)
		for index, device in ipairs(slots) do device.dataPathSize = sizes[index] or 0 end
		done()
	end)
end

-- Runs validated commands one at a time, revalidating each target first.
function Controller:run(commands, targets, validate)
	self.busy = true; self:show()
	local generation = self.generation
	local function step(index)
		if index > #commands then
			self.changed()
			if generation == self.generation then self.busy = false; self:load() end
			return
		end
		if not validate(targets[index]) then
			if generation == self.generation then self.busy = false; self:show() end
			return
		end
		self.service.command(commands[index], function(ok, output)
			if not ok then
				self.changed()
				if generation == self.generation then
					self.busy = false; self.error = "Action failed: " .. tostring(output):sub(1, 220); self:show()
				end
				return
			end
			step(index + 1)
		end)
	end
	step(1)
	return true
end

function Controller:perform(action, unavailable)
	if self.busy then return false end
	local targets = unavailable and Simulators.rows(self.inventory, nil, "Unavailable") or {self.selected}
	local commands, names = {}, {}
	for _, row in ipairs(targets) do
		local command = Simulators.command(action, row, self.model)
		if not command then return false end
		table.insert(commands, command); table.insert(names, row.name .. " · " .. row.id)
	end
	if #commands == 0 then return false end
	local title = unavailable and "Delete unavailable simulators" or action == "erase" and "Erase simulator contents" or "Delete simulator device"
	local message = unavailable and (table.concat(names, "\n") .. "\n\nThese devices cannot use their current runtime. Their apps and data may still be valuable. Permanently deletes ONLY these devices and their contents. Installed runtimes are preserved. This cannot be undone.") or Simulators.impact(action, self.selected)
	if not self.service.confirmAction(title, message) then return false end
	return self:run(commands, targets, function(row) return Simulators.validate(action, row, self.model) end)
end

function Controller:deleteRuntime()
	if self.busy then return false end
	local row = self.selectedRuntime
	local command = Simulators.runtimeCommand(row, self.model)
	if not command then return false end
	if not self.service.confirmAction("Delete simulator runtime", Simulators.runtimeImpact(row)) then return false end
	return self:run({command}, {row}, function(target) return Simulators.validateRuntime(target, self.model) end)
end

function Controller:dispose()
	self.generation = self.generation + 1
	self.busy = false
	if self.template then self.template:dispose() end
	self.template, self.refs, self.selected, self.selectedRuntime = nil, nil, nil, nil
end

return Controller
