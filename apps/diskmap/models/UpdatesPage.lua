local DataModel = require("data.model")
local Model = require("apps.diskmap.Model")
local Updates = require("apps.diskmap.models.Updates")
local Recommendations = require("apps.diskmap.models.Recommendations")

-- The Updates & Snapshots page. Software Update's record is read when the
-- page opens; local snapshots and installer files arrive asynchronously, and
-- each says so with `services.refresh()`. Nothing here is removed by hand,
-- so every action only navigates or reveals.
local UpdatesPage = DataModel.define({})
UpdatesPage.queries = {openCleanup = true, openSoftwareUpdate = true, openTimeMachine = true, installerMenu = true, revealInstaller = true}

function UpdatesPage.new(_, services)
	return setmetatable({services = services, service = services.service, storage = services.model, generation = 0}, UpdatesPage)
end

function UpdatesPage:activate()
	local service = self.service
	self.generation = self.generation + 1
	local generation = self.generation
	self.plist = service.softwareUpdateStatus and service.softwareUpdateStatus() or nil
	if type(service.findInstallers) == "function" then
		service.findInstallers(self.storage.home, function(files)
			if generation ~= self.generation then return end
			self.installerFiles = files or {}
			self.services.refresh()
		end)
	else
		self.installerFiles = {}
	end
	if service.snapshotCount then
		service.snapshotCount(function(_, dates)
			if generation ~= self.generation then return end
			self.snapshotDates = dates or false
			self.services.refresh()
		end)
	else
		self.snapshotDates = false
	end
	self.services.refresh()
end

-- Results of a visit are not the next visit's: the page computes until the
-- new answers arrive.
function UpdatesPage:deactivate()
	self.generation = self.generation + 1
	self.plist, self.snapshotDates, self.installerFiles = nil, nil, nil
end

-- The space an update needs comes from Clean Up, with the amount it estimates.
function UpdatesPage:decision(data)
	local cleanup = Recommendations.presentation(self.storage, "", self.services.cleanupSources and self.services.cleanupSources() or {})
	local waiting = data.softwareUpdate.known and #data.softwareUpdate.updates > 0
	return {id = "decision", icon = "sparkles", color = "systemIndigo",
		title = waiting and ("Make room for " .. data.softwareUpdate.updates[1].name .. " in Clean Up") or "Free space for the next update in Clean Up",
		detail = "Installing needs room beyond the download, and macOS does not publish how much. Staged update files below belong to macOS and shrink on their own; Clean Up ranks what you can remove instead.",
		amount = Model.size(cleanup.eligibleBytes), amountCaption = "could recover",
		actionTitle = "Open Clean Up", action = "openCleanup"}
end

function UpdatesPage:data()
	-- The installers and snapshots are asked for each visit; the page is drawn when both answer.
	if self.installerFiles == nil or self.snapshotDates == nil then return {computing = "Looking for installers and local snapshots…"} end
	local disk = self.service.diskSpace and self.service.diskSpace(self.storage.home)
	local data = Updates.presentation(self.storage, self.plist, self.snapshotDates, self.installerFiles, disk and disk.freeKb and disk.freeKb * 1024 or nil)
	data.decision = self:decision(data)
	if #data.installers > 0 then data.lists = {installers = self.services.actions:annotate(data.installers, nil, "systemGray")} end
	return data
end

function UpdatesPage:openCleanup() self.services.show("cleanup") end
function UpdatesPage:openSoftwareUpdate() self.service.openSettings("softwareupdate") end
function UpdatesPage:openTimeMachine() self.service.openSettings("timemachine") end
function UpdatesPage:revealInstaller(_, _, row) if row then self.service.reveal(row.path) end end

function UpdatesPage:installerMenu(_, _, row)
	return self.services.actions:folder(row, nil, {path = row.path, name = row.name, bytes = row.bytes, source = "Installers",
		consequence = "An installer you can download again. Installed apps and macOS are not affected."})
end

return UpdatesPage
