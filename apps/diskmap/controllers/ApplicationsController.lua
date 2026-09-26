local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Applications = require("apps.diskmap.models.Applications")
local Controller = {}; Controller.__index = Controller

-- The Applications page and the app facts other pages need. Bundle info and
-- the installed-identifier list load in the background once per set of
-- discovered bundles; `changed()` asks the root to present them.
function Controller.new(model, service, actions, changed)
	return setmetatable({model = model, service = service, actions = actions, changed = changed or function() end,
		filterIndex = 1}, Controller)
end

function Controller:focus(filterIndex) self.filterIndex = filterIndex or 1 end

-- Loads bundle info for the currently discovered apps, once per bundle set,
-- and the installed identifiers once per session.
function Controller:load()
	local paths = {}
	for _, bundle in ipairs(Applications.bundles(self.model)) do table.insert(paths, bundle.path) end
	table.sort(paths)
	local key = table.concat(paths, "\n")
	if key ~= self.loadedKey and rawget(self.service, "applicationInfo") then
		self.loadedKey = key
		self.service.applicationInfo(paths, function(info)
			if self.loadedKey ~= key then return end
			self.info = info; self.changed()
		end)
	end
	if not self.installedRequested and rawget(self.service, "installedBundleIds") then
		self.installedRequested = true
		self.service.installedBundleIds(function(ids)
			self.installed = ids; self.changed()
		end)
	end
end

-- Summary for the Clean Up page; nil until the scan has measured data folders.
function Controller:summary()
	if not self.model.files then return nil end
	local rows = Applications.rows(self.model, self.info, "All")
	return Applications.summary(rows, Applications.leftovers(self.model, self.installed))
end

function Controller:trashLeftover(row)
	local ok, reason = Applications.validateLeftover(self.model, self.installed, row.path)
	if not ok then self.service.showError("Cannot move to Trash", reason.message); return end
	if not self.service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
		row.size .. ". No installed app uses this identifier, but an app on another disk or reinstalled later would lose these settings and data. Moving to Trash does not free space until you empty it.") then return end
	local moved, message = self.service.trash(row.path)
	if not moved then self.service.showError("Could not move to Trash", message or "macOS protects some containers. Remove it in Finder instead."); return end
	self.changed(true)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Applications.etlua", ns)
	local _, refs = self.template:update({filters = Applications.filters, actions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:update(self.state) end,
		appMenu = function(_, _, row) return self.actions:application(row) end,
		leftoverMenu = function(_, _, row) return self.actions:folder(row, function(value) self:trashLeftover(value) end) end,
		revealApp = function(_, _, row) if row then self.service.reveal(row.path) end end,
		revealLeftover = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	self.refs = refs
	self:load()
	self:update(state)
	return refs
end

function Controller:update(state)
	self.state = state
	local refs = self.refs
	if not refs then return end
	refs.filter.selectedSegment = self.filterIndex - 1
	local query = state and state.query
	local rows = Applications.rows(self.model, self.info, Applications.filters[self.filterIndex], query)
	refs.apps:replaceRows(rows)
	local leftovers = Applications.leftovers(self.model, self.installed, query)
	refs.leftovers:replaceRows(leftovers or {})
	refs.leftoversSection.hidden = not leftovers or #leftovers == 0
	local all = Applications.rows(self.model, self.info, "All")
	local summary = Applications.summary(all, Applications.leftovers(self.model, self.installed))
	refs.summary.text = summary.count == 0 and "No applications measured yet."
		or string.format("%d apps use %s, and their data another %s.", summary.count, Model.size(summary.apps), Model.size(summary.data))
	refs.appsTileValue.text = Model.size(summary.apps)
	refs.appsTileDetail.text = summary.count .. " application bundles"
	refs.dataTileValue.text = self.model.files and Model.size(summary.data) or "—"
	refs.unusedTileValue.text = self.info and tostring(summary.unused) or "—"
	refs.unusedTileDetail.text = self.info and ("Apps not opened in 6 months · " .. Model.size(summary.unusedBytes)) or "Reading last-used dates…"
	refs.leftoversTileValue.text = summary.leftovers and Model.size(summary.leftoverBytes) or "—"
	refs.leftoversTileDetail.text = summary.leftovers and (summary.leftovers .. " folders of apps not installed") or "Checking installed apps…"
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
