local Inventories = require("apps.diskmap.models.Inventories")
local Model = require("data.model")
local Applications = require("apps.diskmap.models.Applications")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")

-- Decisions first: data left behind by apps that are gone, then the
-- installed apps as the inventory that explains them.
local routes = {}

local LAYOUT = {
	subtitle = "Reading installed applications…",
	leads = {"lead"},
	sections = {
		{id = "leftoversSection", title = "Possible leftovers",
			detail = "Data folders no app on this Mac claims. High means no app from that vendor is installed; review Medium and Low before removing anything. Reinstalling the app starts it fresh.",
			list = {id = "leftovers", menu = "rowMenu", activate = "reveal", detailColumn = true}},
		{title = "Installed", detailId = "installedDetail", detail = "Each app with the data it keeps in your Library.",
			list = {id = "apps", menu = "rowMenu", activate = "reveal", detailColumn = true}},
	},
	footnote = {text = "Last used comes from Spotlight, as Finder's Last Opened; an app without a recorded date reads Last use unknown and is never counted as unused. Apps outside /Applications and ~/Applications are not listed; their data never counts as a leftover."},
}

local WAITING = {title = "Applications Not Measured Yet", systemImage = "square.grid.3x3", description = "Apps and the data they keep are listed when the scan finishes."}
local LINKS = {cleanup = {page = "cleanup"}, reviewMarked = {handler = "review"}}


local function trashLeftover(page, row)
	local service = page.app.service
	local ok, reason = Applications:validateLeftover(row.path)
	if not ok then service.showError("Cannot move to Trash", reason.message); return end
	if not service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
		row.size .. ". No installed app uses this identifier, but an app on another disk or reinstalled later would lose these settings and data. Moving to Trash does not free space until you empty it.") then return end
	local moved, message = service.trash(row.path)
	page.app.log("Move to Trash", moved, row.bytes, row.path, message)
	if not moved then service.showError("Could not move to Trash", message or "macOS protects some containers. Remove it in Finder instead."); return end
	page.app.trashed(row.path, row.bytes)
end

-- The Applications page and the app facts other pages need. Bundle info and
-- the installed-identifier list load in the background once per set of
-- discovered bundles, and the page is drawn again when they arrive.
routes.applications = ListRoute.extend({layout = LAYOUT, children = {lead = "sections/Decision"}, load = function(page)
		page.app.inventories:load("applications")
		if (page.stock.pending or 0) > 0 then page.app.refresh() end
	end,
	menu = function(page, row)
		if not row.tier then return page.rowActions:application(row) end
		return page.rowActions:folder(row, function(value) trashLeftover(page, value) end, Applications.leftoverItem(row))
	end,
	markHigh = function(page)
		return page.rowActions:bulk(page.visibleLeftovers or {}, function(row) return row.tier == "high" end, Applications.leftoverItem)
	end,
	init = function(page) ListRoute.init(page); page.stock = Inventories:state("applications") end,	present = function(page)
		local model = Model.db
		-- Nothing is listed until the scan has measured the apps and Spotlight has told their facts.
		page.visibleLeftovers = {}
		if model.scan.running then return {waiting = WAITING} end
		if (page.stock.pending or 0) > 0 then return {computing = "Reading installed applications…"} end
		local leftovers = Applications:leftovers()
		page.visibleLeftovers = leftovers or {}
		local unmarkedHigh, markedHigh = 0, 0
		for _, row in ipairs(leftovers or {}) do
			local item = Applications.leftoverItem(row)
			row.source, row.consequence = item.source, item.consequence
			if row.tier == "high" then
				if page.rowActions:isIncluded(row.path) then markedHigh = markedHigh + 1 else unmarkedHigh = unmarkedHigh + 1 end
			end
		end
		local apps = Applications:rows()
		local summary = Applications.summary(apps, Applications:leftovers())
		return {lists = {apps = apps,
			leftovers = page.rowActions:annotate(leftovers or {})}, links = LINKS,
			hidden = {leftoversSection = not leftovers or #leftovers == 0},
			children = {lead = Applications.decision(summary, unmarkedHigh, markedHigh, Model.db.applicationInfo ~= nil)},
			subtitle = summary.count == 0 and "No applications measured yet."
				or string.format("%s %s %s, and their data another %s stored.", Format.plural(summary.count, "app"), summary.count == 1 and "uses" or "use", Format.size(summary.apps), Format.size(summary.data)),
			texts = {
			installedDetail = "Each app with the data it keeps in your Library."
				.. (Model.db.applicationInfo and summary.unused > 0 and (" " .. Format.plural(summary.unused, "app") .. " with a known last use over six months ago, " .. Format.size(summary.unusedBytes) .. " with " .. (summary.unused == 1 and "its" or "their") .. " data.") or "")}}
	end})

return routes
