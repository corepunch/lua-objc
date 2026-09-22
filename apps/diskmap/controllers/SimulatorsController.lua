local ns = require("AppKit")
local xml = require("ui.xml")
local Simulators = require("apps.diskmap.models.Simulators")
local Preferences = require("apps.diskmap.models.Preferences")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service, changed)
	return setmetatable({model = model, service = service, changed = changed, generation = 0, inventory = {}, query = ""}, Controller)
end
function Controller:close()
	self.generation = self.generation + 1
	if self.sheet then ns.dismiss(self.sheet); self.sheet = nil end
	if self.scope then self.scope:close(); self.scope = nil end
	self.refs = nil
end
function Controller:buttons()
	if not self.refs then return end
	local allowed = not self.busy and not self.error and not Preferences.isKept(self.model, "simulators")
	self.refs.erase.enabled = allowed and Simulators.command("erase", self.selected) ~= nil
	self.refs.delete.enabled = allowed and Simulators.command("delete", self.selected) ~= nil
	local count = 0
	for _, row in ipairs(Simulators.rows(self.inventory, nil, "Unavailable")) do if Simulators.command("delete", row) then count = count + 1 end end
	self.refs.unavailable.enabled = allowed and count > 0
	self.refs.refresh.enabled = not self.busy
end
function Controller:update()
	if not self.refs then return end
	for index, filter in ipairs(self.filters) do self.refs["rows" .. index]:replaceRows(Simulators.rows(self.inventory, self.query, filter)) end
	self.selected = nil
	self.refs.status.text = self.busy and "Working…" or self.error or (#Simulators.rows(self.inventory, self.query) == 0 and "No matching devices." or "Device data is reported by simctl; it is not added again to disk totals. Last use is UTC, when recorded.")
	if self.busy then for index in ipairs(self.filters) do self.refs["rows" .. index]:showLoading() end
	else for index in ipairs(self.filters) do self.refs["rows" .. index]:hideLoading() end end
	self:buttons()
end
function Controller:load()
	if self.busy then return end
	self.busy = true; self.error = nil; self.inventory = {}; self:update()
	local generation = self.generation
	self.service.command({"/usr/bin/xcrun", "simctl", "list", "--json"}, function(ok, output)
		if generation ~= self.generation then return end
		self.busy = false
		local decoded, value = pcall(self.service.decode, output)
		if ok and decoded and type(value) == "table" and type(value.devices) == "table" then self.inventory = value
		else self.error = "Simulator inventory unavailable. Check xcode-select and CoreSimulator, then Refresh. " .. tostring(output):sub(1, 180) end
		self:update()
	end)
end
function Controller:perform(action, unavailable)
	if self.busy or self.error or Preferences.isKept(self.model, "simulators") then return false end
	local targets = unavailable and Simulators.rows(self.inventory, nil, "Unavailable") or {self.selected}
	local commands, names = {}, {}
	for _, row in ipairs(targets) do
		local command = Simulators.command(action, row)
		if command then commands[#commands + 1] = command; names[#names + 1] = row.name .. " · " .. row.id end
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
	self.scope = ns.Scope.new()
	ns.Scope.withScope(self.scope, function()
		self.sheet, self.refs = xml.renderFile("apps/diskmap/views/Simulators.etlua", {filters = self.filters, actions = {
			search = function(value) self.query = value; self:update() end, done = function() self:close() end,
			refresh = function() self:load() end, erase = function() self:perform("erase") end,
			delete = function() self:perform("delete") end, unavailable = function() self:perform("delete", true) end,
		}}, ns)
		self.refs.done.keyEquivalent = "\r"
		self.sheet.defaultButtonCell = self.refs.done.cell
		for index in ipairs(self.filters) do self.refs["rows" .. index]:onRowSelect(function(_, _, row) self.selected = row; self:buttons() end) end
		self.refs.tabs:onChange(function() self.selected = nil; self:buttons() end)
	end)
	ns.presentSheet(self.sheet, parent); ns.focus(self.sheet, self.refs.search); self:load()
end
return Controller
