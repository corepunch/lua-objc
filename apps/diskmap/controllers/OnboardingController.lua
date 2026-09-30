local ns = require("AppKit")
local xml = require("ui.xml")
local Sheet = require("apps.diskmap.Sheet")
local Controller = {}; Controller.__index = Controller

-- First-launch access onboarding (#52, after Headroom's), shown before the
-- first scan when the provider can tell that access is missing. It has two
-- stages. "disk" comes first in the App Store build while Diskmap has no
-- access to the startup disk: the App Sandbox shows it only what the person
-- chooses in an open panel, whatever Full Disk Access says. It returns on
-- every launch until the disk is chosen, as a scan without it measures
-- nothing. "fullDisk" asks once for Full Disk Access; while it is open
-- Diskmap checks access every second and, once it is granted, closes the
-- sheet and starts the scan by itself. "Continue Without Access" is always
-- there. `finished(granted)` starts the scan.
Controller.interval = 1

function Controller.new(service, finished)
	return setmetatable({service = service, finished = finished}, Controller)
end

local function call(service, name, ...)
	local fn = rawget(service, name)
	if type(fn) == "function" then return fn(...) end
end

-- "disk" while a provider that can tell (the sandboxed Mac) has no access
-- to the startup disk, otherwise "fullDisk".
function Controller:stage()
	if call(self.service, "hasDiskAccess") == false then return "disk" end
	return "fullDisk"
end

-- Needed when the provider reports access (a real Mac does; the synthetic
-- disk does not) and it is missing: the disk on every launch, Full Disk
-- Access until onboarding has been shown.
function Controller:needed()
	if type(rawget(self.service, "hasFullDiskAccess")) ~= "function" then return false end
	if self:stage() == "disk" then return true end
	if call(self.service, "loadFlag", "onboarded") == true then return false end
	return self.service.hasFullDiskAccess() ~= true
end

function Controller:render()
	return xml.renderFile("apps/diskmap/views/Onboarding.etlua", {stage = self:stage(), openedSettings = self.openedSettings == true, actions = {
		chooseDisk = function() self:chooseDisk() end,
		openSettings = function() self:openSettings() end,
		restart = function() self:restart() end,
		skip = function() self:finish(false) end,
	}}, ns)
end

function Controller:open(parent)
	self.parent = parent
	self.sheet, self.refs = Sheet.present(function() return self:render() end, parent)
	-- Headless tests call poll() themselves instead of waiting.
	if not _G.__headless and not self.polling then
		self.polling = true
		ns.async(function()
			while self.sheet do
				ns.sleep(Controller.interval)
				if self.sheet then self:poll() end
			end
			self.polling = false
		end)
	end
end

-- Continues once Full Disk Access has been granted. Returns whether it did.
function Controller:poll()
	if not self.sheet or self:stage() ~= "fullDisk" then return false end
	if self.service.hasFullDiskAccess() == true then self:finish(true); return true end
	return false
end

-- The open panel for the startup disk. Once it is chosen the sheet moves on
-- to Full Disk Access, or closes when that is already on.
function Controller:chooseDisk()
	if not call(self.service, "requestDiskAccess") then return false end
	if self.service.hasFullDiskAccess() == true or call(self.service, "loadFlag", "onboarded") == true then
		self:finish(self.service.hasFullDiskAccess() == true)
		return true
	end
	ns.dismiss(self.sheet)
	self.sheet, self.refs = nil, nil
	self:open(self.parent)
	return true
end

function Controller:openSettings()
	self.service.openSettings("privacy")
	self.openedSettings = true
	if self.refs then self.refs.waiting.hidden = false; self.refs.restart.hidden = false end
end

-- Starts a new instance and quits once it runs; the new one skips the
-- sheet if access now works, or shows it again.
function Controller:restart()
	local relaunch = rawget(self.service, "relaunch")
	if type(relaunch) ~= "function" then return false end
	relaunch(function(message) self.service.showError("Diskmap could not restart", message or "Quit and open Diskmap again.") end)
	return true
end

function Controller:finish(granted)
	if not self.sheet then return end
	call(self.service, "saveFlag", "onboarded", true)
	ns.dismiss(self.sheet)
	self.sheet, self.refs = nil, nil
	self.finished(granted)
end

return Controller
