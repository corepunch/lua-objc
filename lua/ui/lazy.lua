-- SwiftUI's LazyVStack and LazyVGrid: a virtualized collection
-- (src/shared/lazy_collection.m) that builds an item's view with
-- `itemFactory(index)` only when the item scrolls into view. With
-- `reorderable`, dragging an item reports `onReorder(difference)`.
-- install() adds the constructors to a platform module.
local Lazy = {}

function Lazy.install(ns, bridge, applyLayout)
	local function collection(props, isGrid)
		props = props or {}
		assert(type(props.itemFactory) == "function", "lazy collection requires itemFactory")
		local onMove
		if props.reorderable then
			assert(type(props.onReorder) == "function", "lazy collection requires onReorder")
			local Difference = require("ui.reorder").Difference
			onMove = function(from, to)
				props.onReorder(Difference.new():move(from, to))
			end
		end
		local view = bridge._lazyCollection(props.itemCount or 0, props.columns,
			props.rowHeight, props.spacing, props.itemFactory, onMove, isGrid)
		return applyLayout(view, props)
	end

	--- A vertical stack that builds rows only as they scroll into view.
	--- @prop itemCount number required. Number of rows.
	--- @prop itemFactory function required. `itemFactory(index)` returns the row's view.
	--- @prop rowHeight number optional. Row height in points.
	--- @prop spacing number optional. Gap between rows in points.
	--- @prop reorderable boolean optional. Rows reorder by dragging.
	--- @prop onReorder function optional. `onReorder(difference)` after a drag.
	--- @platform AppKit and UIKit.
	function ns.LazyVStack(props)
		return collection(props, false)
	end

	--- A vertical grid that builds cells only as they scroll into view.
	--- @prop itemCount number required. Number of cells.
	--- @prop itemFactory function required. `itemFactory(index)` returns the cell's view.
	--- @prop columns number optional. Columns per row.
	--- @prop rowHeight number optional. Row height in points.
	--- @prop spacing number optional. Gap between cells in points.
	--- @prop reorderable boolean optional. Cells reorder by dragging.
	--- @prop onReorder function optional. `onReorder(difference)` after a drag.
	--- @platform AppKit and UIKit.
	function ns.LazyVGrid(props)
		return collection(props, true)
	end
end

return Lazy
