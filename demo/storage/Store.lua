-- The demo's store: the tables its models read (lua/data/model.lua), as a
-- database holds them. Every launch starts from this data.
return function()
	return {
		folders = {
			{name = "Developer", icon = "hammer.fill", bytes = 56.4e9},
			{name = "Music", icon = "music.note", bytes = 21.1e9},
			{name = "Documents", icon = "doc.fill", bytes = 14.0e9},
			{name = "Downloads", icon = "arrow.down.circle.fill", bytes = 180e6},
			{name = "Library", icon = "books.vertical.fill", denied = true},
			{name = "Caches", icon = "memorychip", calculating = true},
		},
		settings = {
			{id = "device", history = false, deviceName = "My Mac", threshold = 0},
		},
	}
end
