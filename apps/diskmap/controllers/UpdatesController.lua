local Page = require("apps.diskmap.controllers.PageController")
local Updates = require("apps.diskmap.models.Updates")
local Controller = Page.extend("updates", "Updates")

-- The Updates & Snapshots page. Software Update's record is read when the
-- page opens; local snapshots arrive asynchronously from tmutil.
function Controller.new(model, service, actions)
	return setmetatable({model = model, service = service, actions = actions}, Controller)
end

function Controller:mount(host, state)
	self:attach(host)
	self.plist = self.service.softwareUpdateStatus and self.service.softwareUpdateStatus() or nil
	self.snapshotDates = nil
	self.installerFiles = nil
	self:update(state)
	local generation = self.generation
	if type(self.service.findInstallers) == "function" then
		self.service.findInstallers(self.model.home, function(files)
			if generation ~= self.generation then return end
			self.installerFiles = files or {}
			self:update(state)
		end)
	else
		self.installerFiles = {}
	end
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
	local disk = self.service.diskSpace and self.service.diskSpace(self.model.home)
	local free = disk and disk.freeKb and disk.freeKb * 1024 or nil
	local data = Updates.presentation(self.model, self.plist, self.snapshotDates, self.installerFiles, free)
	data.installersLoading = self.installerFiles == nil
	data.actions = {
		openSoftwareUpdate = function() self.service.openSettings("softwareupdate") end,
		openTimeMachine = function() self.service.openSettings("timemachine") end,
	}
	data.actions.installerMenu = function(_, _, row)
		return self.actions:folder(row, nil, {path = row.path, name = row.name, bytes = row.bytes, source = "Installers",
			consequence = "An installer you can download again. Installed apps and macOS are not affected."})
	end
	data.actions.revealInstaller = function(_, _, row) if row then self.service.reveal(row.path) end end
	local refs = self:render(data)
	if refs.installers then
		local rows = {}
		for _, installer in ipairs(data.installers) do
			table.insert(rows, {id = installer.path, path = installer.path, name = installer.name, bytes = installer.bytes, size = installer.size,
				subtitle = installer.path, detail = installer.type,
				icon = installer.kind == "macOS installer app" and "app.dashed" or "opticaldiscdrive"})
		end
		refs.installers:replaceRows(self.actions:annotate(rows, nil, "systemGray"))
	end
end

function Controller:marksChanged() self:update() end

return Controller
