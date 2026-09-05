local Model = {}

Model.title = "Lua + ObjC Demo"
Model.subtitle = "A SwiftUI-like API backed by native AppKit controls."
Model.version = "1.0"
Model.timestamp = os.date("%Y-%m-%d %H:%M")

Model.contacts = {
	{ name = "Alice",   role = "Engineer",     active = true  },
	{ name = "Bob",     role = "Designer",     active = true  },
	{ name = "Charlie", role = "Manager",      active = false },
	{ name = "Diana",   role = "Engineer",     active = true  },
	{ name = "Eve",     role = "Data Analyst", active = true  },
}

return Model
