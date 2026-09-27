local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Volumes = require("apps.diskmap.models.Volumes")
local VolumeContents = require("apps.diskmap.models.VolumeContents")
local Controller = {}; Controller.__index = Controller

-- Disks & Volumes: drive health, the APFS volumes of the startup container
-- and other mounted disks. Everything is read-only; repairs happen in Disk
-- Utility. Disk facts are reread each time the page opens.
function Controller.new(service, actions)
	return setmetatable({service = service, actions = actions, generation = 0}, Controller)
end

function Controller:mount(host, state)
	self.generation = self.generation + 1
	self.template = Template.new(host, "apps/diskmap/views/Disks.etlua", ns)
	self:render()
	local generation = self.generation
	if rawget(self.service, "volumes") then
		self.service.volumes(function(volumes)
			if generation ~= self.generation or not self.template then return end
			self.volumes = volumes
			self:render()
		end)
	end
	return self.refs
end

function Controller:render()
	local volumes = self.volumes or {}
	local _, refs = self.template:update({health = Volumes.health(volumes.info), actions = {
		diskUtility = function() self.service.openDiskUtility() end,
		volumeMenu = function(_, _, row) return {{title = "Copy Device Identifier", systemImage = "doc.on.doc", action = function() self.service.copy(row.detail) end}} end,
		externalMenu = function(_, _, row)
			local items = {{title = "Analyze Contents", systemImage = "chart.bar.doc.horizontal", action = function() self:analyze(row) end}}
			for _, item in ipairs(self.actions:folder(row)) do table.insert(items, item) end
			return items
		end,
		revealExternal = function(_, _, row) if row then self:analyze(row) end end,
		contentsMenu = function(_, _, row) return self:contentsMenu(row) end,
		revealContents = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	self.refs = refs
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

function Controller:dispose()
	self.generation = self.generation + 1
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
