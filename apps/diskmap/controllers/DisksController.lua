local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Volumes = require("apps.diskmap.models.Volumes")
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
		externalMenu = function(_, _, row) return self.actions:folder(row) end,
		revealExternal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	self.refs = refs
	local info = volumes.info or {}
	local apfs = Volumes.apfs(volumes.apfs, info.APFSContainerReference)
	refs.volumes:replaceRows(apfs and apfs.rows or {})
	refs.volumesSection.hidden = apfs == nil
	local external = Volumes.external(volumes.external)
	refs.external:replaceRows(external)
	refs.externalSection.hidden = #external == 0
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

function Controller:update() end

function Controller:dispose()
	self.generation = self.generation + 1
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
