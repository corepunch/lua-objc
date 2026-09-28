-- A calendar heatmap like a contribution graph: `HeatmapCell` records fill
-- columns of `rows` cells top to bottom, left to right (a week per column by
-- default). Each cell is a small native view in `tint`, with its opacity
-- stepped into `levels` bands of the largest value; empty cells show the
-- quaternary fill.
--
--   <HeatmapGrid tint="systemGreen" accessibilityLabel="142 commits this year">
--     <% for _, day in ipairs(days) do %>
--       <HeatmapCell value="<%= day.count %>" label="<%= day.date %>" />
--     <% end %>
--   </HeatmapGrid>
local Component = require("ui.component")

-- Cell metrics follow the compact grids in Apple's Health and Fitness
-- summaries. Level 1 starts faint and each level adds equal opacity.
local STYLE = { rows = 7, cellSize = 11, spacing = 3, cornerRadius = 2, levels = 4, empty = "quaternaryLabel",
	minimumOpacity = 0.3 }

local HeatmapGrid = {
	props = { rows = "num", cellSize = "num", spacing = "num", levels = "num", tint = "str" },
	records = { HeatmapCell = { value = "num", label = "str" } },
}

-- The level (0 for empty, 1...levels) of each record: its value's share of
-- the largest value, rounded up so any activity is visible.
function HeatmapGrid.levels(records, levels)
	levels = math.max(1, math.floor(tonumber(levels) or STYLE.levels))
	local largest = 0
	for _, record in ipairs(records or {}) do largest = math.max(largest, tonumber(record.value) or 0) end
	local result = {}
	for index, record in ipairs(records or {}) do
		local value = tonumber(record.value) or 0
		result[index] = (value > 0 and largest > 0) and math.max(1, math.ceil(value / largest * levels)) or 0
	end
	return result
end

-- The color and opacity a cell at `level` of `levels` draws with.
function HeatmapGrid.style(level, levels, tint)
	if level <= 0 then return STYLE.empty, 1 end
	levels = math.max(1, math.floor(tonumber(levels) or STYLE.levels))
	local step = levels > 1 and (level - 1) / (levels - 1) or 1
	return tint or "accent", STYLE.minimumOpacity + (1 - STYLE.minimumOpacity) * step
end

-- Records split into columns of `rows` cells.
function HeatmapGrid.columns(count, rows)
	rows = math.max(1, math.floor(tonumber(rows) or STYLE.rows))
	return math.ceil(count / rows), rows
end

local function paint(ns, view, level, props)
	local color, opacity = HeatmapGrid.style(level, props.levels, props.tint)
	view.backgroundColor = ns.Color(color)
	view.opacity = opacity
end

function HeatmapGrid.build(self, ns)
	local size = self.props.cellSize or STYLE.cellSize
	local spacing = self.props.spacing or STYLE.spacing
	local levels = HeatmapGrid.levels(self.records, self.props.levels)
	local columns, rows = HeatmapGrid.columns(#self.records, self.props.rows)
	local grid = Component.frame(self, { spacing = spacing, alignment = "top" })
	self.cells = {}
	for column = 1, columns do
		local stack = { spacing = spacing, alignment = "leading" }
		for row = 1, rows do
			local index = (column - 1) * rows + row
			if index > #self.records then break end
			local color, opacity = HeatmapGrid.style(levels[index], self.props.levels, self.props.tint)
			local cell = ns.VStack { fixedWidth = size, fixedHeight = size,
				background = color, opacity = opacity, cornerRadius = STYLE.cornerRadius }
			local label = self.records[index].label
			if label then cell.accessibilityLabel = label end
			self.cells[index] = cell
			table.insert(stack, cell)
		end
		table.insert(grid, ns.VStack(stack))
	end
	return ns.HStack(grid)
end

-- The same number of cells repaints in place; a different count or shape
-- rebuilds the grid.
function HeatmapGrid.accepts(self, props, records)
	return #records == #self.cells and (props.rows or STYLE.rows) == (self.props.rows or STYLE.rows)
		and (props.cellSize or STYLE.cellSize) == (self.props.cellSize or STYLE.cellSize)
		and (props.spacing or STYLE.spacing) == (self.props.spacing or STYLE.spacing)
end

function HeatmapGrid.update(self, ns)
	local levels = HeatmapGrid.levels(self.records, self.props.levels)
	for index, cell in ipairs(self.cells) do
		paint(ns, cell, levels[index], self.props)
		cell.accessibilityLabel = self.records[index].label or ""
	end
end

return HeatmapGrid
