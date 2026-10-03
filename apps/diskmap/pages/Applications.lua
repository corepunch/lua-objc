local Model = require("data.model")
local Provider = require("apps.diskmap.services.Provider")
local Applications = require("apps.diskmap.models.Applications")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")

-- Decisions first: data left behind by apps that are gone, then the
-- installed apps as the inventory that explains them.
local routes = {}

local LAYOUT = {
	summary = "Reading installed applications…",
	leads = {"lead"},
	sections = {
		{id = "leftoversSection", title = "Possible leftovers",
			detail = "Data folders no app on this Mac claims. High means no app from that vendor is installed; review Medium and Low before removing anything. Reinstalling the app starts it fresh.",
			list = {id = "leftovers", menu = "rowMenu", activate = "reveal", detailColumn = true}},
		{title = "Installed", detailId = "installedDetail", detail = "Each app with the data it keeps in your Library.",
			filters = {id = "filter", options = Applications.filters},
			list = {id = "apps", menu = "rowMenu", activate = "reveal", detailColumn = true}},
	},
	footnote = {text = "Last used comes from Spotlight, as Finder's Last Opened; an app without a recorded date reads Last use unknown and is never counted as unused. Apps outside /Applications and ~/Applications are not listed; their data never counts as a leftover."},
}

local WAITING = {title = "Applications Not Measured Yet", systemImage = "square.grid.3x3", description = "Apps and the data they keep are listed when the scan finishes."}
local LINKS = {cleanup = {page = "cleanup"}, reviewMarked = {handler = "review"}}

-- `leftover` lets the cleanup skip it if its app is installed again.
local function leftoverItem(row)
	return {path = row.path, name = row.name, bytes = row.bytes, source = "Leftovers · " .. row.source, leftover = true,
		consequence = "Settings, caches and documents of an app that is no longer installed. Reinstalling the app starts it fresh. Confidence: "
			.. row.confidence .. " (" .. row.reason .. ")."}
end

local function trashLeftover(page, row)
	local service = page.app.service
	local ok, reason = Applications:validateLeftover(row.path)
	if not ok then service.showError("Cannot move to Trash", reason.message); return end
	if not service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
		row.size .. ". No installed app uses this identifier, but an app on another disk or reinstalled later would lose these settings and data. Moving to Trash does not free space until you empty it.") then return end
	local moved, message = service.trash(row.path)
	if not moved then service.showError("Could not move to Trash", message or "macOS protects some containers. Remove it in Finder instead."); return end
	page.app.trashed(row.path, row.bytes)
end

-- The Applications page and the app facts other pages need. Bundle info and
-- the installed-identifier list load in the background once per set of
-- discovered bundles, and the page is drawn again when they arrive.
routes.applications = ListRoute.extend({layout = LAYOUT, children = {lead = "sections/Decision"}, load = function(page)
		page:loadFacts()
		if (page.pending or 0) > 0 then page.app.refresh() end
	end,
	menu = function(page, row)
		if not row.tier then return page.rowActions:application(row) end
		return page.rowActions:folder(row, function(value) trashLeftover(page, value) end, leftoverItem(row))
	end,
	-- File Types and Clean Up open the page on one filter.
	focus = function(page, filterIndex) page.filterIndex = filterIndex or 1 end,
	unusedFilter = function(page) page.filterIndex = 2 end,
	markHigh = function(page)
		local items = {}
		for _, row in ipairs(page.visibleLeftovers or {}) do
			if row.tier == "high" then table.insert(items, leftoverItem(row)) end
		end
		page.rowActions:markAll(items)
	end,
	-- Loads bundle info for the currently discovered apps, once per bundle
	-- set, and the installed identifiers once per session.
	loadFacts = function(page)
		local service, paths = page.app.service, {}
		for _, bundle in ipairs(Applications:all()) do table.insert(paths, bundle.path) end
		table.sort(paths)
		local key = table.concat(paths, "\n")
		if key ~= page.loadedKey and Provider.offers(service, "applicationInfo") then
			page.loadedKey, page.pending = key, (page.pending or 0) + 1
			service.applicationInfo(paths, function(info)
				page.pending = page.pending - 1
				if page.loadedKey == key then Model.db.applicationInfo = info; page.app.refresh() end
			end)
		end
		if not page.installedRequested and Provider.offers(service, "installedBundleIds") then
			page.installedRequested, page.pending = true, (page.pending or 0) + 1
			service.installedBundleIds(function(ids) page.pending = page.pending - 1; Model.db.installedBundleIds = ids; page.app.refresh() end)
		end
	end,
	-- Summary for the Clean Up page; nil until the scan has measured data folders.
	summary = function(page)
		local model = Model.db
		if not model.files or model.files.measuring then return nil end
		return Applications.summary(Applications:rows("All"), Applications:leftovers())
	end, present = function(page, state)
		local model = Model.db
		-- Nothing is listed until the scan has measured the apps and Spotlight has told their facts.
		page.visibleLeftovers = {}
		if model.scan.running then return {waiting = WAITING} end
		if (page.pending or 0) > 0 then return {computing = "Reading installed applications…"} end
		local leftovers = Applications:leftovers(state.query)
		page.visibleLeftovers = leftovers or {}
		local unmarkedHigh, markedHigh = 0, 0
		for _, row in ipairs(leftovers or {}) do
			if row.tier == "high" then
				if page.rowActions:isIncluded(row.path) then markedHigh = markedHigh + 1 else unmarkedHigh = unmarkedHigh + 1 end
			end
		end
		local summary = Applications.summary(Applications:rows("All"), Applications:leftovers())
		return {lists = {apps = Applications:rows(Applications.filters[page.filterIndex], state.query),
			leftovers = page.rowActions:annotate(leftovers or {})}, links = LINKS,
			hidden = {leftoversSection = not leftovers or #leftovers == 0},
			children = {lead = Applications.decision(summary, unmarkedHigh, markedHigh, Model.db.applicationInfo ~= nil)}, texts = {
			summary = summary.count == 0 and "No applications measured yet."
				or string.format("%s %s %s, and their data another %s stored.", Format.plural(summary.count, "app"), summary.count == 1 and "uses" or "use", Format.size(summary.apps), Format.size(summary.data)),
			installedDetail = "Each app with the data it keeps in your Library."
				.. (Model.db.applicationInfo and summary.unused > 0 and (" " .. Format.plural(summary.unused, "app") .. " with a known last use over six months ago, " .. Format.size(summary.unusedBytes) .. " with " .. (summary.unused == 1 and "its" or "their") .. " data.") or "")}}
	end})

return routes
