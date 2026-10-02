local Categories = require("apps.diskmap.models.Categories")
local Applications = require("apps.diskmap.models.Applications")
local Provider = require("apps.diskmap.services.Provider")
local Reminder = require("apps.diskmap.helpers.Reminder")
local Sentinel = require("apps.diskmap.helpers.Sentinel")
local Notifications = {}; Notifications.__index = Notifications

-- The two opt-in notifications: the monthly reminder (#15) and the Sentinel
-- offer after an app is moved to the Trash (#14). Both need the app bundle's
-- notification center; the reminder also needs storage history.
-- `handlers.mark(items)` marks items for cleanup and `handlers.review()`
-- opens the Marked sheet; `handlers.show()` brings the window forward.
function Notifications.new(model, service, handlers)
	return setmetatable({model = model, service = service, handlers = handlers}, Notifications)
end

local function call(service, name, ...)
	local fn = Provider.offers(service, name)
	if type(fn) == "function" then return fn(...) end
end

function Notifications:available()
	return call(self.service, "notificationsAvailable") == true
end

function Notifications:enabled(name)
	return call(self.service, "loadFlag", name) == true
end

-- Turns a notification feature on or off. Turning one on asks macOS for
-- permission first; the switch reports whether it stuck.
function Notifications:setEnabled(name, enabled, done)
	if not enabled then
		call(self.service, "saveFlag", name, false)
		self:apply()
		if done then done(false) end
		return
	end
	call(self.service, "requestNotifications", function(granted)
		if granted then call(self.service, "saveFlag", name, true) end
		self:apply()
		if done then done(granted == true) end
	end)
end

-- Starts or stops the Sentinel watch and schedules or withdraws the reminder
-- to match the saved flags.
function Notifications:apply()
	local sentinel = self:available() and self:enabled("sentinel")
	if sentinel and not self.watcher then
		self.trash = self.model.home .. "/.Trash"
		self.watcher = call(self.service, "watch", {self.trash}, function(events) self:trashed(events) end)
	elseif not sentinel and self.watcher then
		self.watcher.cancel()
		self.watcher = nil
	end
	if not (self:available() and self:enabled("reminder")) then call(self.service, "removeNotification", Reminder.id) end
end

-- Reschedules the monthly reminder from the newest history.
function Notifications:historyRecorded(entries)
	if not (self:available() and self:enabled("reminder")) then return end
	local notification = Reminder.notification(Categories:changes(entries, Reminder.days, Reminder.limit))
	if notification then
		call(self.service, "notify", notification, function() self.handlers.show() end)
	end
end

function Notifications:trashed(events)
	for _, app in ipairs(Sentinel.trashedApps(events, self.trash)) do
		local plist = call(self.service, "readPropertyList", app .. "/Contents/Info.plist")
		local bundleId = type(plist) == "table" and plist.CFBundleIdentifier or nil
		local folders, bytes = Applications:data(bundleId, Sentinel.name(app))
		local offer = Sentinel.offer(app, bundleId, folders, bytes)
		if offer then
			call(self.service, "notify", offer.notification, function(_, action)
				self.handlers.show()
				if action == "action" then
					local items = {}
					for _, folder in ipairs(offer.folders) do
						table.insert(items, {path = folder.path, name = offer.name .. " · " .. folder.label, bytes = folder.bytes,
							source = "Deleted app", consequence = "Settings, caches and documents of " .. offer.name
								.. ", which you moved to the Trash. Reinstalling it starts fresh."})
					end
					self.handlers.mark(items)
				end
				self.handlers.review()
			end)
		end
	end
end

function Notifications:stop()
	if self.watcher then self.watcher.cancel(); self.watcher = nil end
end

return Notifications
