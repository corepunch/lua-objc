-- The demo's two pages (lua/data/routes.lua): each asks its models for what
-- its view shows; an action changes a model, then the page is asked again.
local Routes = require("data.routes")
local Folders = require("demo.storage.models.Folders")
local Settings = require("demo.storage.models.Settings")

return {
	folders = {
		view = "Folders",
		data = function(self)
			local rows, scans = Folders:visible(), self.scans or 0
			return {lists = {folders = rows}, summary = string.format("%d folder%s", #rows, #rows == 1 and "" or "s")
				.. (scans > 0 and ", scanned " .. scans .. "×" or "")}
		end,
		rescan = function(self) self.scans = (self.scans or 0) + 1 end,
	},
	settings = {
		view = "Settings",
		before = function(self) self.settings = Settings:current() end,
		data = function(self)
			local settings = self.settings
			return {history = settings.history, deviceName = settings.deviceName, threshold = settings.threshold,
				thresholds = Settings.thresholds, note = "History is " .. tostring(settings.history) .. "; name is " .. settings.deviceName}
		end,
		setHistory = function(self, value) self.settings:update({history = value == true}) end,
		setDeviceName = function(self, value) Routes.assert(self.settings:update({deviceName = value})) end,
		setThreshold = function(self, index) Routes.assert(self.settings:update({threshold = index})) end,
	},
}
