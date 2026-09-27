--[[
  ui/treemap.lua — squarified treemap layout and hit testing.

  Nodes are a flat list: { id, parent, value, color, label, detail, hatched }.
  A node without `parent` is top level. Children are laid out inside their
  parent's rectangle below a one-line header band that holds the parent's
  label, so every level stays readable, the way Finder-like treemaps nest
  folders. Label placement is computed here, not in the native view, so the
  no-overlap contract between a header and its children is unit tested. Layout is the Bruls–Huizing–van Wijk
  squarified algorithm: rows along the shorter side, keeping aspect ratios
  near 1. Everything is plain arithmetic so it is unit tested without views.
]]

local Treemap = {}

-- Nested levels get a header band and a small inset only when there is room
-- for both; smaller parents show their children edge to edge and no label.
-- `labelLine` matches the native 11 pt label line; the band is one line plus
-- a small margin so the parent's text never reaches its first child.
Treemap.metrics = { labelStrip = 20, inset = 2, minNested = 36, maxDepth = 3, minCell = 2,
	labelInset = 5, labelLine = 14, labelMinWidth = 56 }

local function worst(row, sum, side)
	local largest, smallest = 0, math.huge
	for _, area in ipairs(row) do
		if area > largest then largest = area end
		if area < smallest then smallest = area end
	end
	local sum2, side2 = sum * sum, side * side
	return math.max(side2 * largest / sum2, sum2 / (side2 * smallest))
end

-- Lays out `values` (positive, sorted largest first) inside a rectangle and
-- returns one rectangle per value in the same order.
function Treemap.squarify(values, x, y, w, h)
	local rects, total = {}, 0
	for _, v in ipairs(values) do total = total + v end
	if total <= 0 or w <= 0 or h <= 0 then return rects end
	local areas = {}
	for index, v in ipairs(values) do areas[index] = v / total * w * h end
	local i, n = 1, #areas
	while i <= n do
		local side = math.min(w, h)
		local row, rowSum, j = { areas[i] }, areas[i], i + 1
		while j <= n do
			local candidate = { table.unpack(row) }
			table.insert(candidate, areas[j])
			if worst(candidate, rowSum + areas[j], side) <= worst(row, rowSum, side) then
				row, rowSum, j = candidate, rowSum + areas[j], j + 1
			else
				break
			end
		end
		if w >= h then
			local column = rowSum / h
			local cy = y
			for k, area in ipairs(row) do
				local rh = area / column
				rects[i + k - 1] = { x = x, y = cy, w = column, h = rh }
				cy = cy + rh
			end
			x, w = x + column, w - column
		else
			local band = rowSum / w
			local cx = x
			for k, area in ipairs(row) do
				local rw = area / band
				rects[i + k - 1] = { x = cx, y = y, w = rw, h = band }
				cx = cx + rw
			end
			y, h = y + band, h - band
		end
		i = j
	end
	return rects
end

local function childrenOf(nodes)
	local children, roots = {}, {}
	for _, node in ipairs(nodes) do
		if (tonumber(node.value) or 0) > 0 then
			if node.parent ~= nil and node.parent ~= "" then
				children[node.parent] = children[node.parent] or {}
				table.insert(children[node.parent], node)
			else
				table.insert(roots, node)
			end
		end
	end
	return children, roots
end

-- A leaf shows its name on the first line and its detail on the second, each
-- only when the tile has room for the line plus its insets.
local function leafLabels(cell, metrics)
	local width = cell.w - 2 * metrics.labelInset
	if not cell.label or cell.w < metrics.labelMinWidth
		or cell.h < 2 * metrics.labelInset + metrics.labelLine then return end
	local x, y = cell.x + metrics.labelInset, cell.y + metrics.labelInset
	cell.labelFrame = { x = x, y = y, w = width, h = metrics.labelLine }
	if cell.detail and cell.h >= 2 * metrics.labelInset + 2 * metrics.labelLine then
		cell.detailFrame = { x = x, y = y + metrics.labelLine, w = width, h = metrics.labelLine }
	end
end

-- A group with a header band draws name and detail on one line inside it
-- (the native view right-aligns the detail); children start below the band.
local function headerLabels(cell, metrics)
	if not cell.label or cell.w < metrics.labelMinWidth then return end
	cell.header = true
	cell.labelFrame = { x = cell.x + metrics.labelInset, y = cell.y + (metrics.labelStrip - metrics.labelLine) / 2,
		w = cell.w - 2 * metrics.labelInset, h = metrics.labelLine }
end

-- Returns drawable cells, parents before their children, for a canvas of
-- `width` × `height` points.
function Treemap.layout(nodes, width, height, metrics)
	metrics = metrics or Treemap.metrics
	local children, roots = childrenOf(nodes or {})
	local cells = {}
	local function place(list, x, y, w, h, depth)
		table.sort(list, function(a, b)
			if a.value ~= b.value then return a.value > b.value end
			return tostring(a.id) < tostring(b.id)
		end)
		local values, placed = {}, 0
		for index, node in ipairs(list) do values[index] = node.value end
		for index, rect in ipairs(Treemap.squarify(values, x, y, w, h)) do
			local node = list[index]
			if rect.w >= metrics.minCell and rect.h >= metrics.minCell then
				local cell = { id = node.id, x = rect.x, y = rect.y, w = rect.w, h = rect.h, depth = depth,
					color = node.color, label = node.label, detail = node.detail, hatched = node.hatched == true }
				table.insert(cells, cell)
				placed = placed + 1
				local kids, nested = children[node.id], 0
				local banded = rect.h >= metrics.minNested + metrics.labelStrip
				if kids and depth + 1 < metrics.maxDepth
					and rect.w >= metrics.minNested and rect.h >= metrics.minNested then
					local top = banded and metrics.labelStrip or metrics.inset
					nested = place(kids, rect.x + metrics.inset, rect.y + top,
						rect.w - 2 * metrics.inset, rect.h - top - metrics.inset, depth + 1)
				end
				-- Children cover an unbanded parent, so it shows no label at all.
				if nested == 0 then
					leafLabels(cell, metrics)
				elseif banded then
					headerLabels(cell, metrics)
				end
			end
		end
		return placed
	end
	place(roots, 0, 0, width, height, 0)
	return cells
end

-- The deepest cell containing a point, or nil.
function Treemap.hit(cells, x, y)
	if x == nil or y == nil then return nil end
	for index = #cells, 1, -1 do
		local cell = cells[index]
		if x >= cell.x and x < cell.x + cell.w and y >= cell.y and y < cell.y + cell.h then return cell end
	end
end

-- Builds the native view with platform module `ns`. Array entries of `props`
-- are `TreemapNode` records.
function Treemap.view(bridge, applyLayout, props)
	props = props or {}
	local nodes = {}
	for _, child in ipairs(props) do
		if type(child) == "table" and child.__treemapNode then table.insert(nodes, child) end
	end
	local cells = {}
	local view, keys
	local ChartKeys = require("ui.chartkeys")
	local byId = {}
	for _, node in ipairs(nodes) do byId[node.id] = node end
	-- Cells that do not match the typed filter are drawn receding.
	local function annotate()
		for _, cell in ipairs(cells) do
			local node = byId[cell.id]
			cell.dimmed = node ~= nil and keys ~= nil and not keys:matches(node)
		end
		return cells
	end
	view = bridge._treemap(function(width, height)
		cells = Treemap.layout(nodes, width, height)
		return annotate()
	end, function(target, x, y, count)
		local cell = Treemap.hit(cells, x, y)
		if not cell then return end
		target.selectedId = cell.id
		if props.onSelect then props.onSelect(cell.id, count) end
	end, function(target, x, y)
		local cell = Treemap.hit(cells, x, y)
		target.highlightedId = cell and cell.id or nil
		if props.onHover then props.onHover(cell and cell.id or nil) end
	end, props.dragItem and function(_, x, y)
		local cell = Treemap.hit(cells, x, y)
		return cell and props.dragItem(cell.id) or nil
	end, function(_, key) return keys:handle(key) end)
	keys = ChartKeys.new(nodes, {
		focus = function(id)
			view.highlightedId = id
			if props.onHover then props.onHover(id) end
		end,
		activate = function(id) if props.onSelect then props.onSelect(id, 2) end end,
		back = function() if props.onBack then props.onBack() end end,
		filtered = function() bridge._treemapRefresh(view) end,
	})
	if props.selected then view.selectedId = props.selected end
	if props.accessibilityLabel then view.accessibilityLabel = props.accessibilityLabel end
	return applyLayout(view, props)
end

return Treemap
