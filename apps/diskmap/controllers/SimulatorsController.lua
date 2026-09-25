local ns = require("AppKit")
local xml = require("ui.xml")
local Simulators = require("apps.diskmap.models.Simulators")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service, changed)
	return setmetatable({model = model, service = service, changed = changed, generation = 0, inventory = {}, query = ""}, Controller)
end
function Controller:close()
	self.generation = self.generation + 1
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end
function Controller:buttons()
	if not self.refs then return end
	local allowed = not self.busy and not self.error
	self.refs.erase.enabled = allowed and Simulators.command("erase", self.selected, self.model) ~= nil
	self.refs.delete.enabled = allowed and Simulators.command("delete", self.selected, self.model) ~= nil
	local count = 0
	for _, row in ipairs(Simulators.rows(self.inventory, nil, "Unavailable")) do if Simulators.command("delete", row, self.model) then count = count + 1 end end
	self.refs.unavailable.enabled = allowed and count > 0
	self.refs.refresh.enabled = not self.busy
end
function Controller:update()
	if not self.refs then return end
	for index, filter in ipairs(self.filters) do self.refs["rows" .. index]:replaceRows(Simulators.rows(self.inventory, self.query, filter)) end
	self.selected = nil
	self.refs.status.text = self.busy and "Working…" or self.error or (#Simulators.rows(self.inventory, self.query) == 0 and "No matching devices." or "Device data is the size of each simulator folder. It is already included in Simulator devices. Last use comes from device.plist when that file is present.")
	if self.busy then for index in ipairs(self.filters) do self.refs["rows" .. index]:showLoading() end
	else for index in ipairs(self.filters) do self.refs["rows" .. index]:hideLoading() end end
	self:buttons()
end
function Controller:finish(generation, inventory)
	if generation ~= self.generation then return end
	self.busy = false
	if type(inventory) == "table" and type(inventory.devices) == "table" then self.inventory = inventory
	else self.error = "Simulator folders could not be read." end
	self:update()
end
function Controller:load()
	if self.busy then return end
	self.busy = true; self.error = nil; self.inventory = {}; self:update()
	local generation = self.generation
	if type(self.service.simulatorInventory) == "function" then
		self.service.simulatorInventory(self.model.home, function(inventory) self:finish(generation, inventory) end)
		return
	end
	local ok, inventory = pcall(Simulators.discover, self.service, self.model.home)
	if not ok then self:finish(generation, nil); return end
	local paths, slots = {}, {}
	for _, devices in pairs(inventory.devices or {}) do
		for _, device in ipairs(devices) do
			if device.dataPathSize == nil and device.measurePath then
				table.insert(paths, device.measurePath)
				table.insert(slots, device)
			end
		end
	end
	if #paths == 0 or type(self.service.measure) ~= "function" then self:finish(generation, inventory); return end
	self.service.measure(paths, function(sizes)
		if generation ~= self.generation then return end
		for index, device in ipairs(slots) do device.dataPathSize = sizes[index] or 0 end
		self:finish(generation, inventory)
	end)
end
function Controller:perform(action, unavailable)
	if self.busy or self.error then return false end
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
	self.busy = true; self:update()
	local generation = self.generation
	local function run(index)
		if index > #commands then
			self.changed()
			if generation == self.generation then self.busy = false; self:load() end
			return
		end
		local valid = Simulators.validate(action, targets[index], self.model)
		if not valid then
			if generation == self.generation then self.busy = false; self:update() end
			return
		end
		self.service.command(commands[index], function(ok, output)
			if not ok then
				self.changed()
				if generation == self.generation then self.busy = false; self.error = "Action failed: " .. tostring(output):sub(1, 220); self:update() end
				return
			end
			run(index + 1)
		end)
	end
	run(1); return true
end
function Controller:open(parent)
	self:close(); self.busy = false; self.query = ""; self.filters = {"All devices", "Unavailable"}
	self.sheet, self.refs = ns.presentSheet(function()
		local sheet, refs = xml.renderFile("apps/diskmap/views/Simulators.etlua", {filters = self.filters, actions = {
			search = function(value) self.query = value; self:update() end, done = function() self:close() end,
			select = function(_, _, row) self.selected = row; self:buttons() end,
			tabChanged = function() self.selected = nil; self:buttons() end,
			refresh = function() self:load() end, erase = function() self:perform("erase") end,
			delete = function() self:perform("delete") end, unavailable = function() self:perform("delete", true) end,
		}}, ns)
		return sheet, refs
	end, {parent = parent})
	self:load()
end
return Controller
