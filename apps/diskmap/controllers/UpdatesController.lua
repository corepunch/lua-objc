local ns = require("AppKit")
local Template = require("ui.template")
local Updates = require("apps.diskmap.models.Updates")
local Controller = {}; Controller.__index = Controller

-- The Updates & Snapshots page. Software Update's record is read when the
-- page opens; local snapshots arrive asynchronously from tmutil.
function Controller.new(model, service)
	return setmetatable({model = model, service = service, generation = 0}, Controller)
end

function Controller:mount(host, state)
	self.generation = self.generation + 1
	self.template = Template.new(host, "apps/diskmap/views/Updates.etlua", ns)
	self.plist = self.service.softwareUpdateStatus and self.service.softwareUpdateStatus() or nil
	self.snapshotDates = nil
	self:update(state)
	local generation = self.generation
	if self.service.snapshotCount then
		self.service.snapshotCount(function(_, dates)
			if generation ~= self.generation then return end
			self.snapshotDates = dates or false
			self:update(state)
		end)
	else
		self.snapshotDates = false
	end
	return self.refs
end

-- Re-renders only when the presented values change, so scan progress on
-- other categories leaves the page untouched.
function Controller:update()
	if not self.template then return end
	local data = Updates.presentation(self.model, self.plist, self.snapshotDates)
	data.actions = {
		openSoftwareUpdate = function() self.service.openSettings("softwareupdate") end,
		openTimeMachine = function() self.service.openSettings("timemachine") end,
	}
	for index, installer in ipairs(data.installers) do
		data.actions["reveal_" .. index] = function() self.service.reveal(installer.path) end
	end
	local _, refs = self.template:update(data)
	self.refs = refs
end

function Controller:dispose()
	self.generation = self.generation + 1
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
