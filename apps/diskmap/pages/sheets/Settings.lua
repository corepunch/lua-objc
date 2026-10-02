local Provider = require("apps.diskmap.services.Provider")
local Model = require("data.model")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")

-- The settings sheet: switches over the app's persisted flags. `rescan`
-- restarts measurement after a setting changes what is scanned;
-- `app.notifications` (services/Notifications.lua) owns the opt-in
-- notifications. A switch flips before its action runs, so `sync` sets every
-- switch from the model after each draw: a refused change flips it back.
local routes = {}

local Settings = SheetRoute.extend({view = "sheets/Settings", width = 460, height = 684})
routes.settings = Settings

local MEDIA = {
	mock = "Include the synthetic Photos, Music and TV libraries? Mock HDD reads only its bundled fixture.",
	system = "Measuring Photos, Music and TV libraries requires enumerating their files. macOS may ask for access. Diskmap reads metadata only, and keeps measuring them until you turn this off.",
}

function Settings:init()
	local service = self.app.service
	self.service, self.notifications = service, self.app.notifications
	if type(Provider.offers(service, "loadFlag")) == "function" then Model.db.includeMedia = service.loadFlag("media") == true end
	self.enabled = not service.loadSettings or service.loadSettings()
	self.history = type(Provider.offers(service, "loadHistorySetting")) == "function" and service.loadHistorySetting() == true
end

function Settings:data()
	local available = self.notifications:available()
	self.switches = {monitor = self.enabled, media = Model.db.includeMedia == true, history = self.history,
		reminder = self.notifications:enabled("reminder"), sentinel = self.notifications:enabled("sentinel")}
	return {disabled = {reminder = not available, sentinel = not available}, hidden = {notificationsUnavailable = available}}
end

function Settings:sync(refs)
	for id, on in pairs(self.switches) do refs[id].state = on and 1 or 0 end
end

-- Storage history is opt-in; turning it off also forgets what was recorded.
function Settings:toggleHistory()
	local enabled = not self.history
	if self.service.saveHistorySetting and not self.service.saveHistorySetting(enabled) then
		self.service.showError("Could not save Settings", "Try again.")
		return false
	end
	self.history = enabled
	if not enabled and self.service.saveHistory then self.service.saveHistory("") end
	return true
end

-- The reminder describes storage history, so turning it on turns history on
-- too. The switch stays off when macOS refuses permission.
function Settings:toggleNotification(name)
	local enabled = not self.notifications:enabled(name)
	if enabled and name == "reminder" and not self.history and not self:toggleHistory() then return self:draw() end
	self.notifications:setEnabled(name, enabled, function(on)
		if enabled and not on then
			self.service.showError("Notifications are off for Diskmap", "Allow them in System Settings › Notifications › Diskmap.")
		end
		self:draw()
	end)
	self:draw()
end

function Settings:toggleReminder() self:toggleNotification("reminder") end
function Settings:toggleSentinel() self:toggleNotification("sentinel") end

function Settings:toggle()
	local enabled = not self.enabled
	if self.service.saveSettings and not self.service.saveSettings(enabled) then return false end
	self.enabled = enabled; return true
end

function Settings:toggleMonitor()
	if not self:toggle() then self.service.showError("Could not save Settings", "Try again.") end
end

-- The choice is kept between launches: someone whose disk is full of photos
-- should not have to find the switch again every time.
function Settings:setMedia(enabled)
	Model.db.includeMedia = enabled
	if type(Provider.offers(self.service, "saveFlag")) == "function" then self.service.saveFlag("media", enabled) end
	self.app.rescan()
end

function Settings:toggleMedia()
	if Model.db.includeMedia then return self:setMedia(false) end
	local message = Provider.offers(self.service, "mock") == true and MEDIA.mock or MEDIA.system
	if self.service.confirmAction("Include media libraries", message) then self:setMedia(true) end
end

function Settings:openStorage() self.service.openSettings() end
function Settings:openPrivacy() self.service.openSettings("privacy") end

return routes
