local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Applications = require("apps.diskmap.models.Applications")
local Controller = Page.extend("applications")

-- Decisions first: data left behind by apps that are gone, then the
-- installed apps as the inventory that explains them.
local LAYOUT = {
	summary = "Reading installed applications…",
	leads = {"lead"},
	sections = {
		{id = "leftoversSection", title = "Possible leftovers",
			detail = "Data folders no app on this Mac claims. High means no app from that vendor is installed; review Medium and Low before removing anything. Reinstalling the app starts it fresh.",
			list = {id = "leftovers", menu = "leftoverMenu", activate = "reveal", detailColumn = true}},
		{title = "Installed", detailId = "installedDetail", detail = "Each app with the data it keeps in your Library.",
			filters = {id = "filter", options = Applications.filters},
			list = {id = "apps", menu = "appMenu", activate = "reveal", detailColumn = true}},
	},
	footnote = {text = "Last used comes from Spotlight, as Finder's Last Opened; an app without a recorded date reads Last use unknown and is never counted as unused. Apps outside /Applications and ~/Applications are not listed; their data never counts as a leftover."},
}

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
	if not self.model.files or self.model.files.measuring then return nil end
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

function Controller:leftoverItem(row)
	-- `leftover` lets the cleanup skip it if its app is installed again.
	return {path = row.path, name = row.name, bytes = row.bytes, source = "Leftovers · " .. row.source, leftover = true,
		consequence = "Settings, caches and documents of an app that is no longer installed. Reinstalling the app starts it fresh. Confidence: "
			.. row.confidence .. " (" .. row.reason .. ")."}
end

function Controller:mount(host, state)
	self.pageActions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:update(self.state) end,
		appMenu = function(_, _, row) return self.actions:application(row) end,
		leftoverMenu = function(_, _, row) return self.actions:folder(row, function(value) self:trashLeftover(value) end, self:leftoverItem(row)) end,
		unusedFilter = function() self.filterIndex = 2; self:update(self.state) end,
		cleanup = function() if self.showPage then self.showPage("cleanup") end end,
		markHigh = function()
			local items = {}
			for _, row in ipairs(self.visibleLeftovers or {}) do
				if row.tier == "high" then table.insert(items, self:leftoverItem(row)) end
			end
			self.actions:markAll(items)
		end,
		reviewMarked = function() self.actions.handlers.review() end,
		reveal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}
	local refs = self:attach(host, {layout = LAYOUT, actions = self.pageActions})
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
	self.visibleLeftovers = leftovers or {}
	refs.leftovers:replaceRows(self.actions:annotate(leftovers or {}))
	refs.leftoversSection.hidden = not leftovers or #leftovers == 0
	local unmarkedHigh, markedHigh = 0, 0
	for _, row in ipairs(leftovers or {}) do
		if row.tier == "high" then
			if self.actions:isIncluded(row.path) then markedHigh = markedHigh + 1 else unmarkedHigh = unmarkedHigh + 1 end
		end
	end
	local all = Applications.rows(self.model, self.info, "All")
	local summary = Applications.summary(all, Applications.leftovers(self.model, self.installed))
	refs.summary.text = summary.count == 0 and "No applications measured yet."
		or string.format("%s %s %s, and their data another %s stored.", Model.plural(summary.count, "app"), summary.count == 1 and "uses" or "use", Model.size(summary.apps), Model.size(summary.data))
	refs.installedDetail.text = "Each app with the data it keeps in your Library."
		.. (self.info and summary.unused > 0 and (" " .. Model.plural(summary.unused, "app") .. " with a known last use over six months ago, " .. Model.size(summary.unusedBytes) .. " with " .. (summary.unused == 1 and "its" or "their") .. " data.") or "")
	self.leadRefs = self:decision("lead", self:decisionData(summary, unmarkedHigh, markedHigh))
end

-- The leading decision: leftover data first, because removing it changes
-- nothing an installed app needs; then apps with a known long absence;
-- otherwise where else to look.
function Controller:decisionData(summary, unmarkedHigh, markedHigh)
	local data = {id = "decision", icon = "questionmark.folder.fill", color = "systemGray", actions = self.pageActions}
	if not summary.leftovers then
		data.title, data.detail, data.amount, data.amountCaption = "Checking for data left behind by removed apps…", "Diskmap compares data folders with the apps Spotlight knows.", "—", "to review"
	elseif summary.leftovers > 0 then
		data.title = "Review " .. Model.plural(summary.leftovers, "possible leftover folder")
		data.detail = summary.leftoversHigh > 0
			and (Model.plural(summary.leftoversHigh, "folder") .. " " .. (summary.leftoversHigh == 1 and "is" or "are") .. " likely leftovers: no app from that vendor is known to be installed. Review the other unclaimed folders individually.")
			or "No known installed app claims these folders. A name-only match does not prove its app was removed; review each folder individually."
		if summary.leftoversHighBytes > 0 then data.amount, data.amountCaption = Model.size(summary.leftoversHighBytes), "could recover"
		else data.amount, data.amountCaption = Model.size(summary.leftoverBytes), "to review" end
		if unmarkedHigh > 0 then
			data.actionTitle, data.action = "Mark " .. Model.plural(unmarkedHigh, "Likely Leftover"), "markHigh"
		elseif markedHigh > 0 then
			data.actionTitle, data.action = "Review Marked Items…", "reviewMarked"
		end
		data.secondaryTitle = unmarkedHigh > 0 and markedHigh > 0 and "Review Marked Items…" or nil
		data.secondaryAction = "reviewMarked"
	elseif self.info and summary.unused > 0 then
		data.icon, data.color = "hourglass", "systemOrange"
		data.title = Model.plural(summary.unused, "app") .. " not opened in six months"
		data.detail = "No leftover data was found. These apps have a known last use over six months ago; uninstall them in the Finder or with their own uninstaller if you no longer need them."
		data.amount, data.amountCaption = Model.size(summary.unusedBytes), "to review"
		data.actionTitle, data.action = "Show Unused Apps", "unusedFilter"
	else
		data.icon, data.color = "checkmark.circle.fill", "systemGreen"
		data.title = "No leftover app data"
		data.detail = "Every data folder belongs to an installed app" .. (self.info and ", and no app has gone unused for six months" or "") .. ". Clean Up lists the other places worth reviewing."
		data.amount, data.amountCaption = Model.size(0), "could recover"
		data.actionTitle, data.action = "Open Clean Up", "cleanup"
	end
	return data
end

function Controller:marksChanged() self:update(self.state) end

return Controller
