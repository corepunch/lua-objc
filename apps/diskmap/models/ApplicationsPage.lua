local Model = require("apps.diskmap.Model")
local ListPage = require("apps.diskmap.models.ListPage")
local Applications = require("apps.diskmap.models.Applications")

-- Decisions first: data left behind by apps that are gone, then the
-- installed apps as the inventory that explains them.
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
	local service = page.services.service
	local ok, reason = Applications.validateLeftover(page.storage, page.installed, row.path)
	if not ok then service.showError("Cannot move to Trash", reason.message); return end
	if not service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
		row.size .. ". No installed app uses this identifier, but an app on another disk or reinstalled later would lose these settings and data. Moving to Trash does not free space until you empty it.") then return end
	local moved, message = service.trash(row.path)
	if not moved then service.showError("Could not move to Trash", message or "macOS protects some containers. Remove it in Finder instead."); return end
	page.services.rescan()
end

-- The Applications page and the app facts other pages need. Bundle info and
-- the installed-identifier list load in the background once per set of
-- discovered bundles, and the page is drawn again when they arrive.
return ListPage.class(function()
	return {id = "applications", layout = LAYOUT, children = {lead = "Decision"}, load = function(page)
		page:loadFacts()
		if (page.pending or 0) > 0 then page.services.refresh() end
	end,
	menu = function(page, row)
		if not row.tier then return page.actions:application(row) end
		return page.actions:folder(row, function(value) trashLeftover(page, value) end, leftoverItem(row))
	end,
	actions = {
		-- File Types and Clean Up open the page on one filter.
		focus = function(page, filterIndex) page.filterIndex = filterIndex or 1 end,
		unusedFilter = function(page) page.filterIndex = 2 end,
		markHigh = function(page)
			local items = {}
			for _, row in ipairs(page.visibleLeftovers or {}) do
				if row.tier == "high" then table.insert(items, leftoverItem(row)) end
			end
			page.actions:markAll(items)
		end,
		-- Loads bundle info for the currently discovered apps, once per bundle
		-- set, and the installed identifiers once per session.
		loadFacts = function(page)
			local service, paths = page.services.service, {}
			for _, bundle in ipairs(Applications.bundles(page.storage)) do table.insert(paths, bundle.path) end
			table.sort(paths)
			local key = table.concat(paths, "\n")
			if key ~= page.loadedKey and rawget(service, "applicationInfo") then
				page.loadedKey, page.pending = key, (page.pending or 0) + 1
				service.applicationInfo(paths, function(info)
					page.pending = page.pending - 1
					if page.loadedKey == key then page.info = info; page.services.refresh() end
				end)
			end
			if not page.installedRequested and rawget(service, "installedBundleIds") then
				page.installedRequested, page.pending = true, (page.pending or 0) + 1
				service.installedBundleIds(function(ids) page.pending = page.pending - 1; page.installed = ids; page.services.refresh() end)
			end
		end,
		-- Summary for the Clean Up page; nil until the scan has measured data folders.
		summary = function(page)
			local model = page.storage
			if not model.files or model.files.measuring then return nil end
			return Applications.summary(Applications.rows(model, page.info, "All"), Applications.leftovers(model, page.installed))
		end,
	}, present = function(model, state, page)
		-- Nothing is listed until the scan has measured the apps and Spotlight has told their facts.
		page.visibleLeftovers = {}
		if model.scan.running then return {waiting = WAITING} end
		if (page.pending or 0) > 0 then return {computing = "Reading installed applications…"} end
		local leftovers = Applications.leftovers(model, page.installed, state.query)
		page.visibleLeftovers = leftovers or {}
		local unmarkedHigh, markedHigh = 0, 0
		for _, row in ipairs(leftovers or {}) do
			if row.tier == "high" then
				if page.actions:isIncluded(row.path) then markedHigh = markedHigh + 1 else unmarkedHigh = unmarkedHigh + 1 end
			end
		end
		local summary = Applications.summary(Applications.rows(model, page.info, "All"), Applications.leftovers(model, page.installed))
		return {lists = {apps = Applications.rows(model, page.info, Applications.filters[page.filterIndex], state.query),
			leftovers = page.actions:annotate(leftovers or {})}, links = LINKS,
			hidden = {leftoversSection = not leftovers or #leftovers == 0},
			children = {lead = Applications.decision(summary, unmarkedHigh, markedHigh, page.info ~= nil)}, texts = {
			summary = summary.count == 0 and "No applications measured yet."
				or string.format("%s %s %s, and their data another %s stored.", Model.plural(summary.count, "app"), summary.count == 1 and "uses" or "use", Model.size(summary.apps), Model.size(summary.data)),
			installedDetail = "Each app with the data it keeps in your Library."
				.. (page.info and summary.unused > 0 and (" " .. Model.plural(summary.unused, "app") .. " with a known last use over six months ago, " .. Model.size(summary.unusedBytes) .. " with " .. (summary.unused == 1 and "its" or "their") .. " data.") or "")}}
	end}
end)
