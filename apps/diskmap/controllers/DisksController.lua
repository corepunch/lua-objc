local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Volumes = require("apps.diskmap.models.Volumes")
local VolumeContents = require("apps.diskmap.models.VolumeContents")
local Controller = Page.extend("disks")

-- `health` facts become the tiles once the disk has been read.
local function layout(health)
	local tiles = {}
	for _, fact in ipairs(health) do
		table.insert(tiles, {id = "fact_" .. fact.id, icon = fact.icon, color = fact.color, title = fact.title, value = fact.value, detail = fact.detail})
	end
	return {
		summary = "Reading disk information…",
		buttons = {{id = "diskUtility", title = "Open Disk Utility", action = "diskUtility", help = "Run First Aid or erase a disk in Disk Utility"}},
		tiles = tiles,
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
end

-- Disks & Volumes: drive health, the APFS volumes of the startup container
-- and other mounted disks. Everything is read-only; repairs happen in Disk
-- Utility. Disk facts are reread each time the page opens.
function Controller.new(context)
	return setmetatable({service = context.service, actions = context.actions}, Controller)
end

function Controller:mount(host, state)
	self:attach(host)
	self:show()
	local generation = self.generation
	if rawget(self.service, "volumes") then
		self.service.volumes(function(volumes)
			if generation ~= self.generation or not self.template then return end
			self.volumes = volumes
			self:show()
		end)
	end
	return self.refs
end

function Controller:show()
	local volumes = self.volumes or {}
	local refs = self:render({layout = layout(Volumes.health(volumes.info)), actions = {
		diskUtility = function() self.service.openDiskUtility() end,
		volumeMenu = function(_, _, row) return {{title = "Copy Device Identifier", systemImage = "doc.on.doc", action = function() self.service.copy(row.detail) end}} end,
		externalMenu = function(_, _, row)
			local items = {{title = "Analyze Contents", systemImage = "chart.bar.doc.horizontal", action = function() self:analyze(row) end}}
			for _, item in ipairs(self.actions:folder(row)) do table.insert(items, item) end
			return items
		end,
		analyze = function(_, _, row) if row then self:analyze(row) end end,
		contentsMenu = function(_, _, row) return self:contentsMenu(row) end,
		reveal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	local info = volumes.info or {}
	local apfs = Volumes.apfs(volumes.apfs, info.APFSContainerReference)
	refs.volumes:replaceRows(apfs and apfs.rows or {})
	refs.volumesSection.hidden = apfs == nil
	local external = Volumes.external(volumes.external)
	refs.external:replaceRows(external)
	refs.externalSection.hidden = #external == 0
	self:showContents()
	if not self.volumes then return end
	if apfs then
		refs.containerDetail.text = string.format("%d volumes share %s in container %s; %s is free for all of them.",
			#apfs.rows, Model.size(apfs.capacity), apfs.reference or "", Model.size(apfs.free))
	end
	local name = info.VolumeName or "Startup disk"
	local facts = {}
	if info.FilesystemUserVisibleName then table.insert(facts, info.FilesystemUserVisibleName) end
	if info.DeviceIdentifier then table.insert(facts, info.DeviceIdentifier) end
	refs.summary.text = name .. (#facts > 0 and (" · " .. table.concat(facts, " · ")) or "")
end

-- Measures one external disk's top level: another disk's scope, beside
-- the startup disk Diskmap otherwise describes.
function Controller:analyze(volume)
	if not rawget(self.service, "analyzeFolder") then return end
	self.analyzed = {name = volume.name, path = volume.path, loading = true}
	self:showContents()
	local generation = self.generation
	self.service.analyzeFolder(volume.path, function(entries, failure)
		if generation ~= self.generation or not self.analyzed or self.analyzed.path ~= volume.path then return end
		self.analyzed.loading, self.analyzed.entries, self.analyzed.failure = false, entries or {}, failure
		self:showContents()
	end)
end

function Controller:contentsMenu(row)
	local items = {}
	if row.action == "emptyTrash" then
		table.insert(items, {title = "Empty Trash…", systemImage = "trash", action = function() self:emptyTrash() end})
	elseif row.action == "spotlight" then
		table.insert(items, {title = "Spotlight Settings…", systemImage = "magnifyingglass", action = function() self.service.openSettings("spotlight") end})
	end
	for _, item in ipairs(self.actions:folder(row, nil, not row.system and {path = row.path, name = row.name, bytes = row.bytes,
		source = self.analyzed and self.analyzed.name or "Disk"} or nil)) do table.insert(items, item) end
	return items
end

function Controller:emptyTrash()
	if not self.service.confirmAction("Empty Trash", "Permanently removes everything in the Trash, on every disk. This cannot be undone.") then return end
	self.service.emptyTrash()
	if self.analyzed then self:analyze(self.analyzed) end
end

function Controller:showContents()
	local refs, analyzed = self.refs, self.analyzed
	if not refs then return end
	refs.contentsSection.hidden = analyzed == nil
	if not analyzed then return end
	local rows, total = VolumeContents.rows(analyzed.path, analyzed.entries)
	refs.contents:replaceRows(self.actions:annotate(rows))
	refs.contentsTitle.text = "Contents of " .. analyzed.name
	refs.contentsDetail.text = analyzed.loading and "Measuring…" or analyzed.failure
		or (Model.size(total) .. " in " .. #rows .. " items at the top level. Hidden system folders are explained; their owners manage them.")
end

function Controller:update() end

return Controller
