local Model = {}

function Model.presentation()
	return {
		projects = {
			{name = "playground", detail = "Current project", icon = "app.fill"},
			{name = "HabitPal", detail = "Today, 09:15", icon = "square.grid.2x2"},
			{name = "PixelPaint", detail = "Yesterday", icon = "paintpalette"},
			{name = "StoryWorld", detail = "3 days ago", icon = "book.closed"},
			{name = "Calc+", detail = "1 week ago", icon = "plus.forwardslash.minus"},
		},
		links = {
			{name = "Projects", icon = "folder.fill"},
			{name = "Templates", icon = "square.grid.2x2"},
			{name = "Examples", icon = "shippingbox"},
			{name = "Plugins", icon = "puzzlepiece"},
			{name = "Settings", icon = "gearshape"},
		},
	}
end

return Model
