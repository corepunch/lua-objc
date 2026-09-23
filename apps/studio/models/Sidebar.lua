local Model = {}

function Model.presentation(projects)
	return {
		projects = projects or {
			{name = "playground", title = "playground", detail = "Current project", icon = "app.fill", selected = true},
			{name = "HabitPal", title = "HabitPal", detail = "Today, 09:15", icon = "square.grid.2x2"},
			{name = "PixelPaint", title = "PixelPaint", detail = "Yesterday", icon = "paintpalette"},
			{name = "StoryWorld", title = "StoryWorld", detail = "3 days ago", icon = "book.closed"},
			{name = "Calc+", title = "Calc+", detail = "1 week ago", icon = "plus.forwardslash.minus"},
		},
		links = {
			{name = "Projects", title = "Projects", icon = "folder.fill"},
			{name = "Templates", title = "Templates", icon = "square.grid.2x2"},
			{name = "Examples", title = "Examples", icon = "shippingbox"},
			{name = "Plugins", title = "Plugins", icon = "puzzlepiece"},
			{name = "Settings", title = "Settings", icon = "gearshape"},
		},
	}
end

return Model
