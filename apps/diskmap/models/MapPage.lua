local Model = require("data.model")
local Categories = require("apps.diskmap.models.Categories")
local MapTree = require("apps.diskmap.models.MapTree")
local Selection = require("apps.diskmap.models.Selection")
local Sectors = require("ui.sectors")
local Storage = require("apps.diskmap.Model")

-- The Map page: the semantic tree as rings beside a list of the focused
-- node's children, or as rectangles alone. Clicking a group focuses it, the
-- center or the breadcrumb goes back up. The pointer over a wedge or cell and
-- the list row name one resource (models/Selection.lua), which the native
-- chart and list paint; that pointing is the live part and never draws the
-- page again. `mapStyle` of the services picks the first chart.
local Map = Model.define({id = "map"})

local STYLES = {"rings", "rectangles"}
local DEFAULT_HOVER = "Hover over the map for details; click a group to look inside."

-- The breadcrumb and "worth a look" buttons are named by position
-- (`focus_2`, `worth_1`): the page's current data says what they do.
Map.__index = function(self, key)
	local value = Map[key]
	if value ~= nil then return value end
	local kind, index = tostring(key):match("^(%a+)_(%d+)$")
	index = tonumber(index)
	if kind == "focus" and self.trail and self.trail[index] then return function() self:setFocus(self.trail[index].id) end end
	if kind == "worth" and self.worth and self.worth[index] then return function() self:toggleWorth(self.worth[index]) end end
end

function Map.new(_, services)
	local style = services.mapStyle
	if style ~= "rectangles" then style = "rings" end
	return setmetatable({storage = services.model, services = services, actions = services.actions, focus = "", style = style}, Map)
end

-- Pointing, row menus and drags only read; looking inside draws again.
Map.queries = {chartHover = true, selectRow = true, rowMenu = true, dragPath = true}

local function isGroup(storage, id)
	local resource = id and storage.resources:find(id)
	return resource ~= nil and not resource:isLeaf()
end

-- The view animates the change of focus: the rings move to the new level.
function Map:setFocus(id)
	if id ~= "" and not isGroup(self.storage, id) then return end
	self.focus = id or ""
end

function Map:up()
	local resource = self.focus ~= "" and self.storage.resources:find(self.focus)
	local parent = resource and resource:getParent()
	self:setFocus(parent and parent.id or "")
end

function Map:setStyle(style)
	for _, known in ipairs(STYLES) do
		if known == style then self.style = style; return end
	end
	error("unknown map style " .. tostring(style), 2)
end

function Map:pickStyle(index) self:setStyle(STYLES[(index or 0) + 1]) end

-- The line under the chart names the pointed resource; its row follows.
function Map:point(id)
	self.selectedId = Selection.index(self.rows, id) and id or nil
	if self.refs then
		self.refs.mapHover.text = id and MapTree.describe(self.storage, id, self.total) or self.hover
		Selection.show(self.refs.mapList, self.rows, self.selectedId)
	end
end

function Map:chartHover(id) self:point(id) end

function Map:chartSelect(id, count)
	if count and count > 1 then self:drill(id)
	elseif isGroup(self.storage, id) then self:setFocus(id)
	else self:point(id) end
end

-- A group looks inside; a leaf opens its category sheet.
function Map:drill(id)
	if not id or id:find("#other", 1, true) then return end
	if isGroup(self.storage, id) then self:setFocus(id); return end
	local resource = self.storage.resources:find(id)
	local parent = resource and resource:getParent()
	self.actions.handlers.open(parent and parent.id or id)
end

-- A selected row points at its sector, as hovering the sector would.
function Map:selectRow(_, _, row)
	if not row then return end
	self:point(row.id)
	if self.refs.sunburst then Sectors.highlight(self.refs.sunburst, row.id) end
end

function Map:drillRow(_, _, row) if row then self:drill(row.id) end end

function Map:rowMenu(_, _, row) return self.actions:resource(row.id) end

-- A mark drags as its folder or file, like a Finder item.
function Map:dragPath(id)
	local resource = self.storage.resources:find(id)
	return resource and resource.path
end

function Map:toggleWorth(item)
	if item.included then self.actions.handlers.review(item.enclosingPath); return end
	local resource = self.storage.resources:find(item.id)
	self.actions.review:toggle({path = item.path, name = item.name, bytes = item.bytes, resourceId = item.id,
		source = "Map", consequence = resource and resource.consequence})
end

function Map:data(state)
	local storage = self.storage
	-- While the scan runs nothing is measured yet as far as this page shows;
	-- it is drawn again when the scan finishes.
	local scanning = storage.scan.running == true
	local nodes, total = {}, 0
	if not scanning then nodes, total = MapTree.nodes(storage, self.focus) end
	local trail = MapTree.path(storage, self.focus)
	local query = state.query or ""
	-- Search narrows the list beside the chart, as on every other page; the
	-- chart keeps the whole level so its proportions stay true.
	local rows = scanning and {} or Categories.rows(storage, self.focus ~= "" and self.focus or nil, query)
	table.sort(rows, function(a, b) return (a.bytes or -1) > (b.bytes or -1) end)
	local largest = rows[1] and rows[1].bytes or 0
	for _, row in ipairs(rows) do
		row.children = nil
		row.relative = row.bytes and largest > 0 and row.bytes / largest or nil
		row.shareText = row.bytes and total > 0 and string.format("%d%%", math.floor(row.bytes * 100 / total + 0.5)) or ""
	end
	local worth = scanning and {} or MapTree.worthALook(storage, self.focus, 3)
	for _, item in ipairs(worth) do
		item.markable = self.actions:markableResource(storage.resources:find(item.id))
		item.marked = self.actions:isMarked(item.path)
		local parent, exact = self.actions:covering(item.path)
		item.included = parent ~= nil and not exact
		item.enclosingPath = item.included and parent.path or nil
	end
	self.trail, self.worth, self.rows, self.total = trail, worth, rows, total
	self.hover = #nodes == 0 and "" or DEFAULT_HOVER
	if not Selection.index(rows, self.selectedId) then self.selectedId = nil end
	local focusRow = self.focus ~= "" and Categories.row(storage, self.focus) or nil
	-- The Overview counts what the disk reports as used; the Map counts
	-- what Diskmap measured. Saying both keeps the two pages reconcilable.
	local disk = state.disk
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	return {nodes = nodes, rows = rows, trail = trail, worth = worth, style = self.style, hover = self.hover,
		total = Storage.size(total), query = query,
		-- Rectangles have no list beside them.
		lists = self.style ~= "rectangles" and {mapList = rows} or nil,
		subtitle = (focusRow and (focusRow.name .. " · ") or "") .. Storage.size(total) .. " measured"
			.. (self.focus == "" and (used and used >= total and (" of " .. Storage.size(used) .. " used · shares are of what was measured")
				or " across every category") or ""),
		accessibilityLabel = "Storage map of " .. trail[#trail].name .. ", " .. #nodes .. " areas"}
end

-- Reloading rows drops the native selection; the token restores it.
function Map:rendered(refs)
	self.refs = refs
	Selection.show(refs.mapList, self.rows, self.selectedId)
end

function Map:deactivate() self.refs = nil end

return Map
