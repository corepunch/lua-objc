local FileKind = require("apps.diskmap.helpers.FileKind")
local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local Files = require("apps.diskmap.models.Files")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Scope = require("apps.diskmap.helpers.Scope")
local Selection = require("apps.diskmap.helpers.Selection")
local Sectors = require("ui.sectors")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")

-- The pages that explore where space goes: the Storage Map, Largest
-- Locations and File Types (the Folder Map is pages/Folder.lua).
local routes = {}

-- The Map page: the semantic tree as rings beside a list of the focused
-- node's children, or as rectangles alone. Clicking a group focuses it, the
-- center or the breadcrumb goes back up. The pointer over a wedge or cell and
-- the list row name one resource (helpers/Selection.lua), which the native
-- chart and list paint; that pointing is the live part and never draws the
-- page again. `self.app.mapStyle` picks the first chart.
local map = {view = "pages/Map"}
routes.map = map

local STYLES = {"rings", "rectangles"}
-- The caption under the chart keeps two lines; this must fit them whole in
-- the narrowest pane (tests/diskmap_issue102.test.lua).
map.guidance = "Click a group to look inside. Double-click opens it; actions are below."

-- `/map` is the whole disk and `/map/developer` one group inside it.
function map:focus(params)
	self:setFocus(params.focus or "")
	if params.style then self:setStyle(params.style) end
end
function map:location() return {focus = self.focusId ~= "" and self.focusId or nil} end

function map:init()
	local style = self.app.mapStyle
	if style ~= "rectangles" then style = "rings" end
	self.rowActions, self.focusId, self.style = self:flow("Rows"), "", style
end

-- Pointing, row menus and drags only read; looking inside draws again.
map.queries = {chartHover = true, selectRow = true, rowMenu = true, dragPath = true}

local function isGroup(storage, id)
	local resource = id and Locations:find(id)
	return resource ~= nil and not resource:isLeaf()
end

-- The view animates the change of focus: the rings move to the new level.
function map:setFocus(id)
	if id ~= "" and not isGroup(Model.db, id) then return end
	if self.focusId ~= (id or "") then self.selectedId = nil end
	self.focusId = id or ""
end

function map:up()
	local resource = self.focusId ~= "" and Locations:find(self.focusId)
	local parent = resource and resource:parent()
	self:setFocus(parent and parent.id or "")
end

function map:setStyle(style)
	for _, known in ipairs(STYLES) do
		if known == style then self.style = style; return end
	end
	error("unknown map style " .. tostring(style), 2)
end

function map:pickStyle(index) self:setStyle(STYLES[(index or 0) + 1]) end

-- The hole names the pointed sector and its size, as Apple's SectorMark
-- sample does, and the line under the chart its path; its row follows.
-- (WWDC23 10037, StylesDetailsChart; see lua/ui/sectors.lua.)
function map:point(id)
	if self.refs then
		local node = id and self.nodeById and self.nodeById[id]
		if self.refs.mapCenterTitle then
			self.refs.mapCenterTitle.text = node and node.label or self.center.title
			self.refs.mapCenterDetail.text = node and node.detail or self.center.detail
		end
		self.refs.mapHover.text = id and Categories:describe(id, self.total) or self.hover
		self.pointing = true
		Selection.show(self.refs.mapList, self.rows, id or self.selectedId)
		self.pointing = false
	end
end

function map:chartHover(id) self:point(id) end

function map:chartSelect(id, count)
	if count and count > 1 then self:drill(id)
	elseif isGroup(Model.db, id) then self:setFocus(id)
	else self.selectedId = Locations:find(id) and id or nil; self:point(id); self:showSelection() end
end

-- A leaf keeps its own destination, just as it does in Largest Locations.
function map:drill(id)
	if not id or id:find("#other", 1, true) then return end
	if isGroup(Model.db, id) then self:setFocus(id); return end
	self.app.open(id)
end

-- A selected row points at its sector, as hovering the sector would.
function map:selectRow(_, _, row)
	if not row or self.pointing then return end
	self.selectedId = row.id
	self:point(row.id)
	self:showSelection()
	if self.refs.sunburst then Sectors.highlight(self.refs.sunburst, row.id) end
end

function map:openSelection() self:drill(self.selectedId) end
function map:inspectSelection()
	local row = Locations:find(self.selectedId)
	if row and row.path then self.app.show("folder", {path = row.path}) end
end

-- Selection is the only live value here; hover never changes its action.
function map:showSelection()
	if not self.refs then return end
	local action = self.rowActions:locationAction(self.selectedId)
	self.refs.mapSelection.text = action.detail
	self.refs.mapOpen.title, self.refs.mapOpen.enabled = action.title, self.selectedId ~= nil
	self.refs.mapInspect.enabled = action.path ~= nil
end

function map:drillRow(_, _, row) if row then self:drill(row.id) end end

function map:rowMenu(_, _, row) return self.rowActions:resource(row.id) end

-- A mark drags as its folder or file, like a Finder item.
function map:dragPath(id)
	local resource = Locations:find(id)
	return resource and resource.path
end

function map:toggleWorth(item)
	local resource = Locations:find(item.id)
	self.app.basket:toggle({path = item.path, name = item.name, bytes = item.bytes, resourceId = item.id,
		source = "Map", consequence = resource and resource.advice})
end

function map:data(state)
	local storage = Model.db
	-- While the scan runs nothing is measured yet as far as this page shows;
	-- it is drawn again when the scan finishes.
	local scanning = storage.scan.running == true
	local nodes, total = {}, 0
	if not scanning then nodes, total = Categories:mapNodes(self.focusId) end
	local trail = Categories:path(self.focusId)
	local rows = scanning and {} or Categories:rows(self.focusId ~= "" and self.focusId or nil)
	table.sort(rows, function(a, b) return (a.bytes or -1) > (b.bytes or -1) end)
	local largest = rows[1] and rows[1].bytes or 0
	-- A row has the color of its sector, which may not be its catalog color
	-- (Categories:hues), so the list and the ring read as one.
	local hues = {}
	for _, node in ipairs(nodes) do hues[node.id] = node.color end
	for _, row in ipairs(rows) do
		row.children = nil
		row.color = hues[row.id] or row.color
		row.relative = row.bytes and largest > 0 and row.bytes / largest or nil
		row.shareText = row.bytes and total > 0 and string.format("%d%%", math.floor(row.bytes * 100 / total + 0.5)) or ""
	end
	local worth = scanning and {} or Categories:worthALook(self.focusId, 3)
	for _, item in ipairs(worth) do
		item.markable = self.rowActions:markableResource(Locations:find(item.id))
		item.marked = self.rowActions:isMarked(item.path)
		local parent, exact = self.rowActions:covering(item.path)
		item.included = parent ~= nil and not exact
		-- A location inside a marked folder is already in the plan: its box
		-- shows checked and cannot be cleared on its own.
		item.checked = item.marked or item.included
		item.markable = item.markable and not item.included
		item.markLabel = "Mark " .. item.name .. " for cleanup"
		item.markHelp = item.included and "Included through a marked folder; review it under Marked" or item.markLabel
	end
	self.trail, self.worth, self.rows, self.total = trail, worth, rows, total
	self.nodeById = {}
	for _, node in ipairs(nodes) do self.nodeById[node.id] = node end
	self.center = {title = Format.size(total), detail = #trail > 1 and "Click to go up" or "Measured"}
	-- The breadcrumb and "worth a look" buttons are named by position
	-- (`focus_2`, `worth_1`).
	local handlers = {}
	for index, step in ipairs(trail) do handlers["focus_" .. index] = function() self:setFocus(step.id) end end
	for index, item in ipairs(worth) do handlers["worth_" .. index] = function() self:toggleWorth(item) end end
	self.hover = #nodes == 0 and "" or map.guidance
	if not Selection.index(rows, self.selectedId) and not self.nodeById[self.selectedId] then self.selectedId = nil end
	local focusRow = self.focusId ~= "" and Categories:row(self.focusId) or nil
	-- The Overview counts what the disk reports as used; the Map counts
	-- what Diskmap measured. Saying both keeps the two pages reconcilable.
	local disk = state.disk
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	return {nodes = nodes, rows = rows, trail = trail, worth = worth, style = self.style, hover = self.hover,
		center = self.center,
		selection = self.rowActions:locationAction(self.selectedId), selected = self.selectedId ~= nil,
		-- Rectangles have no list beside them.
		lists = self.style ~= "rectangles" and {mapList = rows} or nil,
		subtitle = (focusRow and (focusRow.name .. " · ") or "") .. Format.size(total) .. " measured"
			.. (self.focusId == "" and (used and used >= total and (" of " .. Format.size(used) .. " used · shares are of what was measured")
				or " across every category") or ""),
		accessibilityLabel = "Storage map of " .. trail[#trail].name .. ", " .. #nodes .. " areas",
		handlers = handlers}
end

-- Reloading rows drops the native selection; the token restores it.
function map:rendered(refs)
	self.refs = refs
	Selection.show(refs.mapList, self.rows, self.selectedId)
	self:showSelection()
end

function map:deactivate() self.refs = nil end



-- Largest Locations: the known locations measured individually, across
-- every category. The ranking stops where individual items stop mattering at
-- a glance; the category lists still show everything.
local LARGEST = {limit = 100}

routes.largest = ListRoute.extend({layout = {summaryId = "largestSummary", scopeNote = Scope.pages.largest,
	sections = {{list = {id = "largest", menu = "rowMenu", activate = "open", selectAction = "select", status = true}}},
	footnote = {text = "Known locations measured individually, across every category. Open an item's menu to show it in Finder, review it, or keep it out of suggestions."},
}, limit = LARGEST.limit})


function routes.largest:present(state)
	local rows = Locations:largest(state.disk, LARGEST.limit)
	local bytes = 0
	for _, row in ipairs(rows) do bytes = bytes + row.bytes end
	local disk = state.disk
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	return {lists = {largest = rows}, texts = {scopeNote = Scope.text("largest", Scans:coverage()), largestSummary = #rows == 0 and "No measured items yet."
		or string.format("The %d largest measured locations use %s%s.", #rows, Format.size(bytes),
			used and used >= bytes and (" of " .. Format.size(used) .. " used") or "")}}
end

-- File Types: extension totals grouped into kinds, with a donut, advice for
-- the largest kind and the top extensions. The selected kind is the page's
-- selection token: its sector, its row, the headline and the top extensions
-- all name it.
local WAITING = {title = "File Types Not Measured Yet", systemImage = "square.grid.2x2", description = "File types are listed when the scan finishes."}
local kinds = {view = "pages/Kinds"}
routes.kinds = kinds
-- Hovering, menus and the lead card's buttons only read or navigate.
kinds.queries = {selectKind = true, chartHover = true, kindMenu = true, openKind = true, showHeadline = true, showInstallers = true, showOld = true,
	cleanup = true, refresh = true}

-- Large Files, narrowed to one kind.
function kinds:showFiles(kind) self.app.show("files", {filter = "All", kind = kind}) end
function kinds:showInstallers() self.app.show("files", {filter = "Installers & archives"}) end
function kinds:showOld() self.app.show("files", {filter = "Unused for a year"}) end
function kinds:cleanup() self.app.show("cleanup") end
function kinds:refresh() self.app.rescan() end
function kinds:showHeadline() if self.headlineId then self:showFiles(self.headlineId) end end
function kinds:openKind(_, _, row) if row then self:showFiles(row.kindId or row.id) end end

function kinds:kindMenu(_, _, row)
	local kindId = row.kindId or row.id
	local kind = FileKind.byId(kindId)
	return {{title = "Show Largest " .. (kind and kind.name or "Files"), systemImage = "doc.fill", action = function() self:showFiles(kindId) end}}
end

-- A row the pointer selected through its sector is only pointed at; one
-- the person selected is the kept kind, and the page is drawn again for it.
function kinds:selectKind(_, _, row)
	if not row or self.pointing or row.id == self.selectedId then return end
	self.selectedId = row.id
	self.app.refresh()
end

-- A click keeps the kind; a click on the kind already kept opens its largest files.
function kinds:chartSelect(id)
	if id == self.selectedId then self:showFiles(id) else self.selectedId = Selection.index(self.kinds, id) and id or nil end
end

-- The pointer over a sector points at its row; leaving the chart returns to
-- the kind that was kept.
-- The hole names the pointed kind and its size, or the kept kind's, as
-- Apple's SectorMark sample names the selected sector or its default.
-- (WWDC23 10037, StylesDetailsChart; see lua/ui/sectors.lua.)
function kinds:chartHover(id)
	local refs = self.refs
	if not refs then return end
	self.pointing = true
	Selection.show(refs.kinds, self.kinds, id or self.selectedId)
	self.pointing = false
	if not id and refs.kindsChart then Sectors.highlight(refs.kindsChart, self.selectedId) end
	local mark = self.markById and self.markById[id or self.selectedId]
	if refs.kindsTotal then
		refs.kindsTotal.text = mark and mark.name or self.center.title
		refs.kindsCaption.text = mark and Format.size(mark.bytes) or self.center.detail
	end
end

function kinds:data()
	local model = Model.db
	local fileState = Files:state()
	self.kinds, self.headlineId = {}, nil
	-- Nothing is listed until the scan has measured the files.
	if fileState == "loading" then return {waiting = WAITING, summary = ""} end
	local kinds, extensions = Files:kinds()
	if fileState == "error" or fileState == "unavailable" then kinds, extensions = {}, {} end
	self.kinds = kinds
	if not Selection.index(kinds, self.selectedId) then self.selectedId = nil end
	local all, marks, labels = 0, {}, {}
	for _, kind in ipairs(kinds) do
		all = all + kind.bytes
		kind.detail = Format.plural(Format.count(kind.count), "file")
		table.insert(marks, {id = kind.id, name = kind.name, color = kind.color, bytes = kind.bytes, size = kind.size, share = kind.shareText})
		table.insert(labels, kind.name .. " " .. kind.size)
	end
	for _, row in ipairs(extensions) do row.detail = Format.plural(Format.count(row.count), "file") end
	-- The headline names the selected kind, or else the largest kind a
	-- person can act on; "Other files" and databases belong to apps.
	local headline, selected
	for _, kind in ipairs(kinds) do
		if kind.id == self.selectedId then headline, selected = kind, kind; break end
	end
	for _, kind in ipairs(kinds) do
		if not headline and kind.id ~= "other" and kind.id ~= "databases" then headline = kind end
	end
	headline = headline or kinds[1]
	self.headlineId = headline and headline.id
	local inventoryNote = "All measured files, including app and system storage; only files in your own folders are offered for review above."
	if headline and headline.removableBytes then
		inventoryNote = headline.size .. " total stored; " .. Format.size(headline.removableBytes) .. " in your own folders. The rest belongs to apps or the system."
	end
	local decision = Files:kindsDecision(kinds)
	local summary = Format.size(all) .. " in files across " .. #kinds .. " kinds"
	if #kinds == 0 then
		if fileState == "empty" then summary = "Scan complete · No files found"
		else summary = "File type results unavailable" end
	elseif model.files and model.files.partial then summary = summary .. " · scan coverage is incomplete" end
	local lists = {extensions = #extensions > 0 and Selection.extensions(extensions, self.selectedId) or nil}
	if #kinds > 0 then lists.kinds = kinds end
	self.markById = {}
	for _, mark in ipairs(marks) do self.markById[mark.id] = mark end
	self.center = {title = Format.size(all), detail = "in files"}
	local kept = self.markById[self.selectedId]
	return {kinds = marks, center = kept and {title = kept.name, detail = Format.size(kept.bytes)} or self.center, scope = Scope.text("kinds", Scans:coverage()), summary = summary, hasExtensions = #extensions > 0,
		accessibilityLabel = "File types: " .. table.concat(labels, ", "), decision = decision, inventoryNote = inventoryNote,
		headline = headline and {title = headline.name .. " · " .. headline.size .. " stored"} or {},
		extensionsDetail = selected and ("The " .. selected.name .. " extensions that use the most space") or "The twelve extensions that use the most space",
		lists = lists}
end

-- After a draw the native selection and the chart follow the token.
function kinds:rendered(refs)
	self.refs = refs
	Selection.show(refs.kinds, self.kinds, self.selectedId)
	if refs.kindsChart then Sectors.highlight(refs.kindsChart, self.selectedId) end
end

function kinds:deactivate() self.refs = nil end


return routes
