local ns = require("AppKit")
local Sheet = require("apps.diskmap.Sheet")
local xml = require("ui.xml")
local Controller = {}; Controller.__index = Controller

local MEDIA = {
	mock = "Include the synthetic Photos, Music and TV libraries in this session? Mock HDD reads only its bundled fixture.",
	system = "Measuring Photos, Music and TV libraries requires enumerating their files. macOS may ask for access. Diskmap reads metadata only. Enable for this session?",
}

-- `rescan` restarts measurement after a setting changes what is scanned;
-- `notifications` (NotificationsController) owns the opt-in notifications.
function Controller.new(service, model, rescan, notifications)
	return setmetatable({service = service, model = model, rescan = rescan, notifications = notifications,
		enabled = not service.loadSettings or service.loadSettings(),
		history = type(rawget(service, "loadHistorySetting")) == "function" and service.loadHistorySetting() == true}, Controller)
end

-- Storage history is opt-in; turning it off also forgets what was recorded.
function Controller:toggleHistory()
	local enabled = not self.history
	if self.service.saveHistorySetting and not self.service.saveHistorySetting(enabled) then
		if self.refs then self.refs.history.state = self.history and 1 or 0 end
		self.service.showError("Could not save Settings", "Try again.")
		return false
	end
	self.history = enabled
	if not enabled and self.service.saveHistory then self.service.saveHistory("") end
	return true
end

-- A notification switch flips before its action runs; it is restored when
-- macOS refuses permission. The reminder describes storage history, so
-- turning it on turns history on too.
function Controller:toggleNotification(name)
	local enabled = not self.notifications:enabled(name)
	if enabled and name == "reminder" and not self.history then
		if not self:toggleHistory() then self.refs[name].state = 0; return end
		if self.refs then self.refs.history.state = 1 end
	end
	self.notifications:setEnabled(name, enabled, function(on)
		if self.refs then self.refs[name].state = on and 1 or 0 end
		if enabled and not on then
			self.service.showError("Notifications are off for Diskmap", "Allow them in System Settings › Notifications › Diskmap.")
		end
	end)
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
	local notifications = self.notifications
	return {monitoring = self.enabled, mediaEnabled = self.model.includeMedia == true, historyEnabled = self.history,
		notificationsAvailable = notifications:available(),
		reminderEnabled = notifications:enabled("reminder"), sentinelEnabled = notifications:enabled("sentinel"), actions = {
		history = function() self:toggleHistory() end,
		reminder = function() self:toggleNotification("reminder") end,
		sentinel = function() self:toggleNotification("sentinel") end,
		monitor = function() self:toggleMonitoring() end,
		media = function() self:toggleMedia() end,
		storage = function() self.service.openSettings() end,
		privacy = function() self.service.openSettings("privacy") end,
		done = function() self:close() end,
	}}
end

function Controller:open(parent)
	self:close()
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/Settings.etlua", self:presentation(), ns)
	end, parent)
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end

return Controller
