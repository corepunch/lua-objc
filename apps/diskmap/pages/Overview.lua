local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local Figures = require("apps.diskmap.helpers.Overview")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Scope = require("apps.diskmap.helpers.Scope")
local Selection = require("apps.diskmap.helpers.Selection")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local Suggestions = require("apps.diskmap.models.Suggestions")

-- The pages that lead the sidebar: the Overview of the disk and Clean Up.
local routes = {}

-- The overview lists every largest item that fits a glance; the Largest Items
-- page shows the full ranking.
local PREVIEW = {largest = 6}

-- The Overview page: the disk's ring and legend, what changed, what could not
-- be measured, the categories and the largest items. Everything is drawn from
-- `data` once the scan has finished. The sector under the pointer is named on
-- the hole of the ring and no list row follows it; a selected category row
-- points at its sector. Every action navigates or points, so none draws the
-- page again.
routes.overview = {view = "pages/Breakdown", queries = setmetatable({}, {__index = function() return true end})}
local overview = routes.overview

function overview:access() self.app.access() end
overview.grantAccess = overview.access
function overview:reclaim() self.app.show("cleanup") end
function overview:showLargest() self.app.show("largest") end
function overview:showAllChanges() self.app.openChanges() end
function overview:exploreFolders() self.app.show("filesystem") end

function overview:open(_, _, row) if row then self.app.open(row.id) end end
overview.openLargest = overview.open

function overview:markRow(_, _, row) self:flow("Rows"):toggleReview(row) end
function overview:categoryButton(_, column, row)
	if column == "review" then self:markRow(nil, column, row) else self:open(nil, column, row) end
end

function overview:largestMenu(_, _, row) return self:flow("Rows"):resource(row.id) end

function overview:select(_, _, row)
	if row then self.selectedId = row.id end
end

-- The ring leads into the Map: a category's sector opens the Map inside it,
-- the folded categories and the center open the whole map. Free and
-- unattributed space have nothing inside to show.
function overview:showMap(id)
	self.app.show("map", {focus = id})
end

function overview:chartSelect(id)
	if id == Categories.folded then self:showMap("")
	elseif Locations:find(id) then self:showMap(id) end
end

function overview:chartCenter() self:showMap("") end

-- The hole names the pointed category and its size, as Apple's SectorMark
-- sample does. Its share is already available in the legend.
-- (WWDC23 10037, StylesDetailsChart; see lua/ui/sectors.lua.)
function overview:chartHover(id)
	local mark = id and self.marks[id]
	if not self.refs then return end
	if self.refs.breakdownTotal then
		self.refs.breakdownTotal.text = mark and mark.label or self.center.title
		self.refs.breakdownCaption.text = mark and Format.size(mark.value) or self.center.detail
	end
	local chart = self.refs.breakdownChart or self.refs.breakdownRectangles
	if chart then chart.toolTip = mark and (mark.label .. " · " .. Format.size(mark.value)) or "" end
end

function overview:data(state)
	local storage, disk = Model.db, state.disk
	local errors = storage.scan.errors or 0
	-- While the scan runs nothing is measured yet as far as this page shows:
	-- the ring is empty, the lists are absent, and everything is drawn when
	-- the scan finishes.
	local scanning = storage.scan.running == true
	local chart = scanning and {marks = {}, legend = {}, explanation = "Diskmap is measuring your storage. Sizes appear when it finishes."}
		or Categories:chart(disk)
	self.marks, self.categoryRows = {}, {}
	for _, mark in ipairs(chart.marks) do self.marks[mark.id] = mark end
	-- A legend row's button is named for its category (`category_developer`).
	local handlers = {}
	for _, row in ipairs(chart.legend or {}) do
		if row.id and row.id ~= Categories.folded then row.action = "category_" .. row.id; handlers["category_" .. row.id] = function() self.app.open(row.id) end end
	end
	local summary = Scans:summary(disk, state.capacity)
	local breakdown = Figures.breakdown(summary, chart, self.app.chartStyle)
	self.center = breakdown.center
	local data = {status = state.status, accessHidden = state.mock == true, accessTitle = errors > 0 and "Review scan access…" or "Scan access…",
		breakdown = breakdown, handlers = handlers, title = state.volumeName, subtitle = summary.short or summary.subtitle or summary.caption,
		leads = summary.lowSpace and {{view = "components/Warning", data = {id = "lowSpace", text = summary.lowSpaceMessage}}} or nil}
	if scanning then return data end
	self.categoryRows = self:flow("Rows"):annotate(Categories:shares(disk))
	if not Selection.index(self.categoryRows, self.selectedId) then self.selectedId = nil end
	local largest = self:flow("Rows"):annotate(Locations:largest(disk, PREVIEW.largest))
	local cloudBytes, cloudFiles = Scans:cloud()
	breakdown.notes = Figures.hidden(disk, state.capacity, state.snapshotCount, errors, cloudBytes, cloudFiles,
		not storage.includeMedia, Scans:protected(state.fullDiskAccess))
	-- Everything no category holds, and why; then what changed.
	local unmeasured = Categories:unmeasured(disk, {fullDiskAccess = state.fullDiskAccess, diskAccess = state.diskAccess,
		snapshotCount = state.snapshotCount, mediaExcluded = not storage.includeMedia})
	data.context = {}
	if #unmeasured.items > 0 then table.insert(data.context, {view = "sections/NotMeasured", data = unmeasured}) end
	if state.changes then table.insert(data.context, {view = "sections/Changes", data = {changes = state.changes}}) end
	data.sections = {{id = "categoriesSection", title = "Categories", detail = Categories:coverage(disk), detailId = "coverage", panelId = "categoriesPanel",
		view = "components/CategoryList", list = {id = "results"}}}
	if #largest > 0 then
		table.insert(data.sections, {id = "largestSection", title = "Largest items", detail = "Individual resources across every category",
			link = {id = "showLargest", title = "Show All", action = "showLargest"},
			list = {id = "largest", menu = "largestMenu", activate = "openLargest", status = true}})
	end
	data.lists = {results = self.categoryRows, largest = #largest > 0 and largest or nil}
	return data
end

-- Reloading rows drops the native selection, which the token restores.
function overview:rendered(refs)
	self.refs = refs
	Selection.show(refs.results, self.categoryRows, self.selectedId)
end

function overview:deactivate() self.refs = nil end

-- Clean Up: what could go, in sections, the top suggestion leading. Where a
-- tip's action leads.
local TIP_LINKS = {settings = {settings = "privacy"}, system = {page = "guide"}, storage = {page = "overview"}}

-- Every section is always present; empty ones are hidden. The first four
-- are Suggestions.sections, by who clears a suggestion.
local SECTIONS = {
	{id = "now", title = "Clear now", detail = "Caches and build data Diskmap moves to the Trash or asks their owner to clear. Review, then clear."},
	{id = "app", title = "Clear in its app", detail = "Caches, downloads and generated data an app or System Settings removes. Each row says where."},
	{id = "restart", title = "Restart or finish an update", detail = "Temporary files, swap and update staging that macOS clears itself at the next restart or once the pending update completes."},
	{id = "decisions", title = "Your decisions", detail = "Files, apps and devices only you can judge, ranked by what they could recover. Size alone never makes data disposable."},
	{id = "context", title = "System-managed", detail = "macOS manages these; no cleanup is offered here.", collapsed = "Show system-managed storage"},
	{id = "checked", title = "Checked and within limits", detail = "Known space hogs below their review threshold, or kept. " .. "Locations absent from this Mac are not listed.", collapsed = "Show checked locations"},
}
local LAYOUT = {
	leads = {"lead"},
	scopeNote = Scope.pages.cleanup,
	sections = {},
	slots = {"tips"},
}
for _, section in ipairs(SECTIONS) do
	table.insert(LAYOUT.sections, {id = "section_" .. section.id, title = section.title, detail = section.detail, collapsed = section.collapsed,
		list = {id = "list_" .. section.id, menu = "rowMenu", activate = "open", selectAction = "select", status = true}})
end

-- How the lead names its action: by what clears the suggestion.
local LEAD_VERBS = {restart = "Restart to clear ", update = "Finish the update to clear ", now = "Clear ", app = "Clear ", decisions = "Review "}

-- The leading decision: the top-ranked suggestion as one sentence, its
-- amount and the button that starts it. With nothing to suggest it says so
-- and routes to the pages where a person can still look.
local function lead(data)
	local row = data.lead
	if not row then
		return {id = "decision", icon = "checkmark.circle.fill", color = "systemGreen", title = "Nothing crossed a review threshold",
			detail = "Large Files and Applications list what only you can judge.", amount = Format.size(0), amountCaption = "could recover",
			actionTitle = "Open Large Files", action = "leadFiles"}
	end
	local verb = LEAD_VERBS[row.remover] or LEAD_VERBS[row.section] or "Review "
	return {id = "decision", icon = row.icon or "sparkles", color = row.color or "systemIndigo",
		title = row.decisionTitle or (verb .. row.name),
		detail = row.id == "simulators" and "Choose the devices to keep, then confirm the extras. Shared runtimes stay." or (row.subtitle or ""),
		amount = row.size, amountCaption = row.shareText,
		actionTitle = row.page and ("Open " .. (row.pageName or "Page") .. "…") or "Review…", action = "leadOpen"}
end

routes.cleanup = ListRoute.extend({layout = LAYOUT, children = {lead = "sections/Decision", tips = "sections/Tips"}, lead = lead})

function routes.cleanup:present(state)
	local data = Suggestions:presentation(self.app.cleanupSources())
	local lists, hidden = {}, {}
	for _, section in ipairs(SECTIONS) do
		lists["list_" .. section.id] = data[section.id]
		hidden["section_" .. section.id] = #data[section.id] == 0
	end
	local tips, links = Scans:tips(state.disk), {}
	for _, tip in ipairs(tips) do links["tip_" .. tip.id] = TIP_LINKS[tip.action] end
	local first = data.lead
	links.leadOpen = first and (first.page and {page = first.page} or {open = first.id}) or nil
	links.leadFiles = {page = "files"}
	return {lists = lists, hidden = hidden, links = links, children = {tips = {tips = tips}, lead = lead(data)}, subtitle = data.summary, texts = {
		scopeNote = Scope.text("cleanup", Scans:coverage()),
	}}
end

return routes
