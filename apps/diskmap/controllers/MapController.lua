local ns = require("AppKit")
local Template = require("ui.template")
local Categories = require("apps.diskmap.models.Categories")
local MapTree = require("apps.diskmap.models.MapTree")
local Model = require("apps.diskmap.Model")
local Controller = {}; Controller.__index = Controller

local STYLES = {"rings", "rectangles"}

-- The Map page: the semantic tree as raised rings or rectangles beside a
-- list of the focused node's children. Clicking a group focuses it, the center or the
-- breadcrumb goes back up, and hovering describes a node without
-- re-rendering the chart. Activating a leaf opens its category sheet; list
-- rows carry the same menu as every other resource list.
-- `style` ("rings" or "rectangles") picks the initial chart; unknown values
-- fall back to rings.
function Controller.new(model, actions, style)
	for _, known in ipairs(STYLES) do if known == style then return setmetatable({model = model, actions = actions, focus = "", style = style}, Controller) end end
	return setmetatable({model = model, actions = actions, focus = "", style = STYLES[1]}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Map.etlua", ns)
	self:update(state)
	return self.refs
end

local function isGroup(model, id)
	local resource = id and model.resources:find(id)
	return resource ~= nil and not resource:isLeaf()
end

-- Drilling in or out shows the new level at once; only measurement animates.
function Controller:setFocus(id)
	if id ~= "" and not isGroup(self.model, id) then return end
	self.focus = id or ""
	self:update(self.state)
end

function Controller:up()
	local resource = self.focus ~= "" and self.model.resources:find(self.focus)
	local parent = resource and resource:getParent()
	self:setFocus(parent and parent.id or "")
end

function Controller:describe(id)
	if not self.refs then return end
	self.refs.mapHover.text = id and MapTree.describe(self.model, id, self.total) or self.defaultHover
end

function Controller:activate(id)
	if not id or id:find("#other", 1, true) then return end
	if isGroup(self.model, id) then self:setFocus(id); return end
	local resource = self.model.resources:find(id)
	local parent = resource and resource:getParent()
	self.actions.handlers.open(parent and parent.id or id)
end

function Controller:presentation()
	local nodes, total = MapTree.nodes(self.model, self.focus)
	self.total = total
	local trail = MapTree.path(self.model, self.focus)
	local rows = Categories.rows(self.model, self.focus ~= "" and self.focus or nil)
	table.sort(rows, function(a, b) return (a.bytes or -1) > (b.bytes or -1) end)
	local largest = rows[1] and rows[1].bytes or 0
	for _, row in ipairs(rows) do
		row.children = nil
		row.relative = row.bytes and largest > 0 and row.bytes / largest or nil
		row.shareText = row.bytes and total > 0 and string.format("%d%%", math.floor(row.bytes * 100 / total + 0.5)) or ""
	end
	local worth = MapTree.worthALook(self.model, self.focus, 3)
	for _, item in ipairs(worth) do
		item.markable = self.actions:markableResource(self.model.resources:find(item.id))
		item.marked = self.actions:isMarked(item.path)
	end
	self.defaultHover = #nodes == 0 and "" or "Hover over the map for details; click a group to look inside."
	local focusRow = self.focus ~= "" and Categories.row(self.model, self.focus) or nil
	return {nodes = nodes, rows = rows, trail = trail, worth = worth, style = self.style, hover = self.defaultHover,
		total = Model.size(total),
		subtitle = (focusRow and (focusRow.name .. " · ") or "") .. Model.size(total) .. " measured"
			.. (self.focus == "" and " across every category" or ""),
		accessibilityLabel = "Storage map of " .. trail[#trail].name .. ", " .. #nodes .. " areas"}
end

-- setStyle("rings" | "rectangles"), as the chart's segmented control does.
function Controller:setStyle(style)
	for _, known in ipairs(STYLES) do
		if known == style then
			self.style = style
			if self.state then self:update(self.state) end
			return
		end
	end
	error("unknown map style " .. tostring(style), 2)
end

function Controller:update(state)
	if not self.template then return end
	self.state = state
	local data = self:presentation()
	local actions = {
		style = function(index) self:setStyle(STYLES[(index or 0) + 1]) end,
		chartSelect = function(id, count) if count and count > 1 then self:activate(id) elseif isGroup(self.model, id) then self:setFocus(id) else self:describe(id) end end,
		chartHover = function(id) self:describe(id) end,
		up = function() self:up() end,
		selectRow = function(_, _, row) if row then self:describe(row.id) end end,
		drillRow = function(_, _, row) if row then self:activate(row.id) end end,
		rowMenu = function(_, _, row) return self.actions:resource(row.id) end,
		-- A mark drags as its folder or file, like a Finder item.
		dragPath = function(id)
			local resource = self.model.resources:find(id)
			return resource and resource.path
		end,
	}
	for index, step in ipairs(data.trail) do
		actions["focus_" .. index] = function() self:setFocus(step.id) end
	end
	for index, item in ipairs(data.worth) do
		actions["worth_" .. index] = function()
			local resource = self.model.resources:find(item.id)
			self.actions.review:toggle({path = item.path, name = item.name, bytes = item.bytes, resourceId = item.id,
				source = "Map", consequence = resource and resource.consequence})
		end
	end
	data.actions = actions
	local _, refs = self.template:update(data)
	self.refs = refs
	refs.mapList:replaceRows(data.rows)
end

function Controller:marksChanged() self:update(self.state) end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
