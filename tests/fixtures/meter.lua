-- The views of one size meter: a level column's native cell
-- (`levelKey`, `valueKey`). `value` leads, `share` (the column's own text)
-- trails, above the bar; frames are in the cell's coordinates.
return function(cell)
	cell:layout()
	return {
		cell = cell, value = cell.valueField, share = cell.textField, bar = cell.levelIndicator,
		spinner = cell.loadingIndicator, symbol = cell.imageView,
	}
end
