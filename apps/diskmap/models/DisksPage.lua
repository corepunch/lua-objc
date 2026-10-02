local Model = require("apps.diskmap.Model")
local Volumes = require("apps.diskmap.models.Volumes")
local VolumeContents = require("apps.diskmap.models.VolumeContents")

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

local function service(page) return page.services.service end

-- Measures one external disk's top level: another disk's scope, beside the
-- startup disk Diskmap otherwise describes.
local function analyze(page, volume)
	if not rawget(service(page), "analyzeFolder") then return end
	local analyzed = {name = volume.name, path = volume.path, loading = true}
	page.analyzed = analyzed
	service(page).analyzeFolder(volume.path, function(entries, failure)
		if page.analyzed ~= analyzed then return end
		analyzed.loading, analyzed.entries, analyzed.failure = false, entries or {}, failure
		page.services.refresh()
	end)
	page.services.refresh()
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
	for _, item in ipairs(page.actions:folder(row, nil, not row.system and {path = row.path, name = row.name, bytes = row.bytes,
		source = page.analyzed and page.analyzed.name or "Disk"} or nil)) do table.insert(items, item) end
	return items
end

return require("apps.diskmap.models.ListPage").class(function()
	return {id = "disks", layout = function(presented)
		local layout = {tiles = presented.tiles}
		for key, value in pairs(LAYOUT) do layout[key] = value end
		return layout
	end, queries = {diskUtility = true, volumeMenu = true, externalMenu = true, contentsMenu = true}, actions = {
		diskUtility = function(page) service(page).openDiskUtility() end,
		volumeMenu = function(page, _, _, row)
			return {{title = "Copy Device Identifier", systemImage = "doc.on.doc", action = function() service(page).copy(row.detail) end}}
		end,
		externalMenu = function(page, _, _, row)
			local items = {{title = "Analyze Contents", systemImage = "chart.bar.doc.horizontal", action = function() analyze(page, row) end}}
			for _, item in ipairs(page.actions:folder(row)) do table.insert(items, item) end
			return items
		end,
		analyze = function(page, _, _, row) if row then analyze(page, row) end end,
		contentsMenu = contentsMenu,
	}, load = function(page)
		local volumes = rawget(service(page), "volumes")
		page.generation = (page.generation or 0) + 1
		local generation = page.generation
		if volumes then volumes(function(read)
			if generation ~= page.generation then return end
			page.volumes = read
			page.services.refresh()
		end) end
	end, unload = function(page) page.generation = page.generation + 1; page.volumes = nil end,
	present = function(_, _, page)
		if not page.volumes and rawget(service(page), "volumes") then return {computing = "Reading disk information…"} end
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
				#apfs.rows, Model.size(apfs.capacity), apfs.reference or "", Model.size(apfs.free))
		end
		local contents = {}
		if analyzed then
			local rows, total = VolumeContents.rows(analyzed.path, analyzed.entries)
			contents = page.actions:annotate(rows)
			texts.contentsTitle = "Contents of " .. analyzed.name
			texts.contentsDetail = analyzed.loading and "Measuring…" or analyzed.failure
				or (Model.size(total) .. " in " .. #rows .. " items at the top level. Hidden system folders are explained; their owners manage them.")
		end
		return {tiles = tiles, texts = texts, lists = {volumes = apfs and apfs.rows or {}, external = external, contents = contents},
			loading = {contents = analyzed and analyzed.loading},
			hidden = {volumesSection = apfs == nil, externalSection = #external == 0, contentsSection = analyzed == nil}}
	end}
end)
