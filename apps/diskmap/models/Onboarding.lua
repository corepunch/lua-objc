local SheetPage = require("apps.diskmap.SheetPage")

-- First-launch access onboarding (#52, after Headroom's), shown before the
-- first scan when the provider can tell that access is missing. It has two
-- stages. "disk" comes first in the App Store build while Diskmap has no
-- access to the startup disk: the App Sandbox shows it only what the person
-- chooses in an open panel, whatever Full Disk Access says. It returns on
-- every launch until the disk is chosen, as a scan without it measures
-- nothing. "fullDisk" asks once for Full Disk Access; while it is open
-- Diskmap checks access every second and, once it is granted, closes the
-- sheet and starts the scan by itself. "Continue Without Access" is always
-- there. `services.onboarded(granted)` starts the scan.
local Onboarding = SheetPage.define({id = "onboarding", view = "Onboarding", width = 580, height = 390})

Onboarding.interval = 1

function Onboarding.new(_, services)
	return setmetatable({services = services, service = services.service}, Onboarding)
end

local function call(service, name, ...)
	local fn = rawget(service, name)
	if type(fn) == "function" then return fn(...) end
end

-- "disk" while a provider that can tell (the sandboxed Mac) has no access
-- to the startup disk, otherwise "fullDisk".
function Onboarding:stage()
	if call(self.service, "hasDiskAccess") == false then return "disk" end
	return "fullDisk"
end

-- Needed when the provider reports access (a real Mac does; the synthetic
-- disk does not) and it is missing: the disk on every launch, Full Disk
-- Access until onboarding has been shown.
function Onboarding:needed()
	if type(rawget(self.service, "hasFullDiskAccess")) ~= "function" then return false end
	if self:stage() == "disk" then return true end
	if call(self.service, "loadFlag", "onboarded") == true then return false end
	return self.service.hasFullDiskAccess() ~= true
end

function Onboarding:data()
	local waiting = self.openedSettings == true
	return {stage = self:stage(), hidden = {waiting = not waiting, restart = not waiting}}
end

function Onboarding:open(parent)
	self.openedSettings = false
	SheetPage.open(self, parent)
	self:every(Onboarding.interval, function() self:poll() end)
end

-- Continues once Full Disk Access has been granted. Returns whether it did.
function Onboarding:poll()
	if not self.sheet or self:stage() ~= "fullDisk" then return false end
	if self.service.hasFullDiskAccess() == true then self:finish(true); return true end
	return false
end

-- The open panel for the startup disk. Once it is chosen the sheet moves on
-- to Full Disk Access, or closes when that is already on.
function Onboarding:chooseDisk()
	if not call(self.service, "requestDiskAccess") then return false end
	if self.service.hasFullDiskAccess() == true or call(self.service, "loadFlag", "onboarded") == true then
		self:finish(self.service.hasFullDiskAccess() == true)
		return true
	end
	self:draw()
	return true
end

function Onboarding:openSettings()
	self.service.openSettings("privacy")
	self.openedSettings = true
	self:draw()
end

-- Starts a new instance and quits once it runs; the new one skips the
-- sheet if access now works, or shows it again.
function Onboarding:restart()
	local relaunch = rawget(self.service, "relaunch")
	if type(relaunch) ~= "function" then return false end
	relaunch(function(message) self.service.showError("Diskmap could not restart", message or "Quit and open Diskmap again.") end)
	return true
end

function Onboarding:skip() self:finish(false) end

function Onboarding:finish(granted)
	if not self.sheet then return end
	call(self.service, "saveFlag", "onboarded", true)
	self:close()
	self.services.onboarded(granted)
end

return Onboarding
