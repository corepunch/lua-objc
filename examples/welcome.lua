Window {
	title = "Welcome to lua-objc",
	width = 520,
	height = 500,
	transparent_titlebar = true,
	VStack {
		Spacer(),
		HStack { Spacer(), Title "Welcome to lua-objc", Spacer() },
		HStack { Spacer(), Text { "A Lua to AppKit UI framework", size = 13 }, Spacer() },
		Spacer(),
		Button { title = "Create New Script" },
		Button { title = "Open Existing Example" },
		Button { title = "Clone Repository" },
		Separator(),
		Text { "Recent", size = 11, weight = "semibold" },
		List {
			width = 480,
			height = 150,
			columns = {
				{ id = "name", title = "Name" },
				{ id = "time", title = "Opened" },
			},
			data = {
				{ name = "hello.lua",   time = "just now" },
				{ name = "list.lua",    time = "8 min ago" },
				{ name = "live.lua",    time = "12 min ago" },
				{ name = "weather.lua", time = "20 min ago" },
			}
		},
		Separator(),
		Toggle { label = "Show this window on launch", is_on = true },
		Spacer(),
	}
}
