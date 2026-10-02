local Provider = require("apps.diskmap.services.Provider")
local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Recommendations = require("apps.diskmap.helpers.Recommendations")
local Updates = require("apps.diskmap.helpers.Updates")
local VolumeContents = require("apps.diskmap.helpers.VolumeContents")
local Volumes = require("apps.diskmap.helpers.Volumes")

-- The System pages: Disks & Volumes and Updates & Snapshots.
local routes = {}

do
	-- Disks & Volumes: drive health, the APFS volumes of the startup container
	-- and other mounted disks. Everything is read-only; repairs happen in Disk
	-- Utility. Disk facts are reread each time the page opens (`load`).
	local LAYOUT = {
		buttons = {{id = "diskUtility", title = "Open Disk Utility", action = "diskUtility", help = "Run First Aid or erase a disk in Disk Utility"}},
		sections = {
			{id = "volumesSection", title = "Startup disk volumes", detailId = "containerDetail",
				detail = "Every volume shares one APFS container and draws from the same free space.",
				list = {id = "volumes", menu = "volumeMenu", detailColumn = true}},
			{id = "externalSection", title = "Other disks",
				detail = "Mounted external drives and disk images. Choose Analyze Contents in a disk’s menu to measure it.",
				list = {id = "external", menu = "externalMenu", activate = "analyze"}},
			{id = "contentsSection", title = "Contents", titleId = "contentsTitle", detailId = "contentsDetail",
				list = {id = "contents", menu = "contentsMenu", activate = "reveal", detailColumn = true}},
		},
		footnote = {icon = "stethoscope", text = "If apps freeze or files go missing, back up and run First Aid in Disk Utility. SSDs never need defragmenting, and FileVault makes erased data unrecoverable, so secure-erase tools are unnecessary."},
	}

	local function service(page) return page.app.service end

	-- Measures one external disk's top level: another disk's scope, beside the
	-- startup disk Diskmap otherwise describes.
	local function analyze(page, volume)
		if not Provider.offers(service(page), "analyzeFolder") then return end
		local analyzed = {name = volume.name, path = volume.path, loading = true}
		page.analyzed = analyzed
		service(page).analyzeFolder(volume.path, function(entries, failure)
			if page.analyzed ~= analyzed then return end
			analyzed.loading, analyzed.entries, analyzed.failure = false, entries or {}, failure
			page.app.refresh()
		end)
		page.app.refresh()
	end

	local function contentsMenu(page, _, _, row)
		local items = {}
		if row.action == "emptyTrash" then
			table.insert(items, {title = "Empty Trash…", systemImage = "trash", action = function()
				local service = service(page)
				if not service.confirmAction("Empty Trash", "Permanently removes everything in the Trash, on every disk. This cannot be undone.") then return end
				service.emptyTrash()
				if page.analyzed then analyze(page, page.analyzed) end
			end})
		elseif row.action == "spotlight" then
			table.insert(items, {title = "Spotlight Settings…", systemImage = "magnifyingglass", action = function() service(page).openSettings("spotlight") end})
		end
		for _, item in ipairs(page.rowActions:folder(row, nil, not row.system and {path = row.path, name = row.name, bytes = row.bytes,
			source = page.analyzed and page.analyzed.name or "Disk"} or nil)) do table.insert(items, item) end
		return items
	end

	routes.disks = ListRoute.extend({layout = function(_, presented)
			local layout = {tiles = presented.tiles}
			for key, value in pairs(LAYOUT) do layout[key] = value end
			return layout
		end, queries = {diskUtility = true, volumeMenu = true, externalMenu = true, contentsMenu = true},
			diskUtility = function(page) service(page).openDiskUtility() end,
			volumeMenu = function(page, _, _, row)
			return {{title = "Copy Device Identifier", systemImage = "doc.on.doc", action = function() service(page).copy(row.detail) end}}
			end,
			externalMenu = function(page, _, _, row)
			local items = {{title = "Analyze Contents", systemImage = "chart.bar.doc.horizontal", action = function() analyze(page, row) end}}
			for _, item in ipairs(page.rowActions:folder(row)) do table.insert(items, item) end
			return items
			end,
			analyze = function(page, _, _, row) if row then analyze(page, row) end end,
			contentsMenu = contentsMenu, load = function(page)
			local volumes = Provider.offers(service(page), "volumes")
			page.generation = (page.generation or 0) + 1
			local generation = page.generation
			if volumes then volumes(function(read)
				if generation ~= page.generation then return end
				page.volumes = read
				page.app.refresh()
			end) end
		end, unload = function(page) page.generation = page.generation + 1; page.volumes = nil end,
		present = function(page)
			if not page.volumes and Provider.offers(service(page), "volumes") then return {computing = "Reading disk information…"} end
			local volumes = page.volumes or {}
			local info = volumes.info or {}
			local tiles = {}
			for _, fact in ipairs(Volumes.health(volumes.info)) do
				table.insert(tiles, {id = "fact_" .. fact.id, icon = fact.icon, color = fact.color, title = fact.title, value = fact.value, detail = fact.detail})
			end
			local apfs = Volumes.apfs(volumes.apfs, info.APFSContainerReference)
			local external = Volumes.external(volumes.external)
			local analyzed = page.analyzed
			local texts = {}
			local facts = {}
			if info.FilesystemUserVisibleName then table.insert(facts, info.FilesystemUserVisibleName) end
			if info.DeviceIdentifier then table.insert(facts, info.DeviceIdentifier) end
			texts.summary = (info.VolumeName or "Startup disk") .. (#facts > 0 and (" · " .. table.concat(facts, " · ")) or "")
			if apfs then
				texts.containerDetail = string.format("%d volumes share %s in container %s; %s is free for all of them.",
					#apfs.rows, Format.size(apfs.capacity), apfs.reference or "", Format.size(apfs.free))
			end
			local contents = {}
			if analyzed then
				local rows, total = VolumeContents.rows(analyzed.path, analyzed.entries)
				contents = page.rowActions:annotate(rows)
				texts.contentsTitle = "Contents of " .. analyzed.name
				texts.contentsDetail = analyzed.loading and "Measuring…" or analyzed.failure
					or (Format.size(total) .. " in " .. #rows .. " items at the top level. Hidden system folders are explained; their owners manage them.")
			end
			return {tiles = tiles, texts = texts, lists = {volumes = apfs and apfs.rows or {}, external = external, contents = contents},
				loading = {contents = analyzed and analyzed.loading},
				hidden = {volumesSection = apfs == nil, externalSection = #external == 0, contentsSection = analyzed == nil}}
		end})
end

-- The Updates & Snapshots page. Software Update's record is read when the
-- page opens; local snapshots and installer files arrive asynchronously, and
-- each says so with `app.refresh()`. Nothing here is removed by hand,
-- so every action only navigates or reveals.
local UpdatesPage = {view = "pages/Updates"}
routes.updates = UpdatesPage
UpdatesPage.queries = {openCleanup = true, openSoftwareUpdate = true, openTimeMachine = true, installerMenu = true, revealInstaller = true}

function UpdatesPage:init()
	self.service, self.generation = self.app.service, 0
end

function UpdatesPage:activate()
	local service = self.service
	self.generation = self.generation + 1
	local generation = self.generation
	self.plist = service.softwareUpdateStatus and service.softwareUpdateStatus() or nil
	if type(service.findInstallers) == "function" then
		service.findInstallers(Model.db.home, function(files)
			if generation ~= self.generation then return end
			self.installerFiles = files or {}
			self.app.refresh()
		end)
	else
		self.installerFiles = {}
	end
	if service.snapshotCount then
		service.snapshotCount(function(_, dates)
			if generation ~= self.generation then return end
			self.snapshotDates = dates or false
			self.app.refresh()
		end)
	else
		self.snapshotDates = false
	end
	self.app.refresh()
end

-- Results of a visit are not the next visit's: the page computes until the
-- new answers arrive.
function UpdatesPage:deactivate()
	self.generation = self.generation + 1
	self.plist, self.snapshotDates, self.installerFiles = nil, nil, nil
end

-- The space an update needs comes from Clean Up, with the amount it estimates.
function UpdatesPage:decision(data)
	local cleanup = Recommendations.presentation("", self.app.cleanupSources and self.app.cleanupSources() or {})
	local waiting = data.softwareUpdate.known and #data.softwareUpdate.updates > 0
	return {id = "decision", icon = "sparkles", color = "systemIndigo",
		title = waiting and ("Make room for " .. data.softwareUpdate.updates[1].name .. " in Clean Up") or "Free space for the next update in Clean Up",
		detail = "Installing needs room beyond the download, and macOS does not publish how much. Staged update files below belong to macOS and shrink on their own; Clean Up ranks what you can remove instead.",
		amount = Format.size(cleanup.eligibleBytes), amountCaption = "could recover",
		actionTitle = "Open Clean Up", action = "openCleanup"}
end

function UpdatesPage:data()
	-- The installers and snapshots are asked for each visit; the page is drawn when both answer.
	if self.installerFiles == nil or self.snapshotDates == nil then return {computing = "Looking for installers and local snapshots…"} end
	local disk = self.service.diskSpace and self.service.diskSpace(Model.db.home)
	local data = Updates.presentation(self.plist, self.snapshotDates, self.installerFiles, disk and disk.freeKb and disk.freeKb * 1024 or nil)
	data.decision = self:decision(data)
	if #data.installers > 0 then data.lists = {installers = self:flow("Rows"):annotate(data.installers, nil, "systemGray")} end
	return data
end

function UpdatesPage:openCleanup() self.app.show("cleanup") end
function UpdatesPage:openSoftwareUpdate() self.service.openSettings("softwareupdate") end
function UpdatesPage:openTimeMachine() self.service.openSettings("timemachine") end
function UpdatesPage:revealInstaller(_, _, row) if row then self.service.reveal(row.path) end end

function UpdatesPage:installerMenu(_, _, row)
	return self:flow("Rows"):folder(row, nil, {path = row.path, name = row.name, bytes = row.bytes, source = "Installers",
		consequence = "An installer you can download again. Installed apps and macOS are not affected."})
end


return routes
