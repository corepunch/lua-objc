local ns = require("AppKit")
local xml = require("ui.xml")
local Controller = {}; Controller.__index = Controller

local MEDIA = {
	mock = "Include the synthetic Photos, Music and TV libraries in this session? Mock HDD reads only its bundled fixture.",
	system = "Measuring Photos, Music and TV libraries requires enumerating their files. macOS may ask for access. Diskmap reads metadata only. Enable for this session?",
}

-- `rescan` restarts measurement after a setting changes what is scanned.
function Controller.new(service, model, rescan)
	return setmetatable({service = service, model = model, rescan = rescan,
		enabled = not service.loadSettings or service.loadSettings()}, Controller)
end

function Controller:toggle()
	local enabled = not self.enabled
	if self.service.saveSettings and not self.service.saveSettings(enabled) then return false end
	self.enabled = enabled; return true
end

function Controller:toggleMonitoring()
	if self:toggle() then return end
	-- A switch flips before its action runs; restore it when saving failed.
	self.refs.monitor.state = self.enabled and 1 or 0
	self.service.showError("Could not save Settings", "Try again.")
end

function Controller:toggleMedia()
	if self.model.includeMedia then
		self.model.includeMedia = false
		self.rescan()
		return
	end
	local message = rawget(self.service, "mock") == true and MEDIA.mock or MEDIA.system
	if self.service.confirmAction("Include media libraries", message) then
		self.model.includeMedia = true
		self.rescan()
	else
		self.refs.media.state = 0
	end
end

function Controller:presentation()
	return {monitoring = self.enabled, mediaEnabled = self.model.includeMedia == true, actions = {
		monitor = function() self:toggleMonitoring() end,
		media = function() self:toggleMedia() end,
		storage = function() self.service.openSettings() end,
		privacy = function() self.service.openSettings("privacy") end,
		done = function() self:close() end,
	}}
end

function Controller:open(parent)
	self:close()
	self.sheet, self.refs = ns.presentSheet(function()
		return xml.renderFile("apps/diskmap/views/Settings.etlua", self:presentation(), ns)
	end, {parent = parent})
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end

return Controller
