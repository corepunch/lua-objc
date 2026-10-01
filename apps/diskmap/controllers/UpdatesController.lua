local Page = require("apps.diskmap.controllers.PageController")
local Updates = require("apps.diskmap.models.Updates")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Model = require("apps.diskmap.Model")
local Controller = Page.extend("updates", "Updates")

-- The Updates & Snapshots page. Software Update's record is read when the
-- page opens; local snapshots arrive asynchronously from tmutil.
-- `showPage(id)` opens a page; `sources()` is what Clean Up's totals use.
function Controller.new(model, service, actions, showPage, sources)
	return setmetatable({model = model, service = service, actions = actions, showPage = showPage, sources = sources}, Controller)
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

-- Nothing on this page is removed by hand, so its decision is a route: the
-- space an update needs comes from Clean Up, with the amount it estimates.
function Controller:decisionData(data)
	local cleanup = Recommendations.presentation(self.model, "", self.sources and self.sources() or {})
	local waiting = data.softwareUpdate and data.softwareUpdate.known and #data.softwareUpdate.updates > 0
	return {id = "decision", icon = "sparkles", color = "systemIndigo",
		title = waiting and ("Make room for " .. data.softwareUpdate.updates[1].name .. " in Clean Up") or "Free space for the next update in Clean Up",
		detail = "Installing needs room beyond the download, and macOS does not publish how much. Staged update files below belong to macOS and shrink on their own; Clean Up ranks what you can remove instead.",
		amount = Model.size(cleanup.eligibleBytes), amountCaption = "could recover",
		actionTitle = "Open Clean Up", action = "openCleanup"}
end

-- Re-renders only when the presented values change, so scan progress on
-- other categories leaves the page untouched.
function Controller:update()
	if not self.template then return end
	local disk = self.service.diskSpace and self.service.diskSpace(self.model.home)
	local free = disk and disk.freeKb and disk.freeKb * 1024 or nil
	local data = Updates.presentation(self.model, self.plist, self.snapshotDates, self.installerFiles, free)
	data.installersLoading = self.installerFiles == nil
	data.decision = self:decisionData(data)
	data.actions = {
		openCleanup = function() if self.showPage then self.showPage("cleanup") end end,
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
