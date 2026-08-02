local Model = {}

Model.navigationItems = {
	{ section = "Overview" },
	{ section = "Activity" },
	{ section = "Reports" },
	{ section = "Settings" },
}

Model.contentItems = {
	{ item = "Declarative layout", owner = "Core", status = "Ready" },
	{ item = "Native tables", owner = "AppKit", status = "Ready" },
	{ item = "Measurement pass", owner = "Core", status = "New" },
	{ item = "Flexible sizing", owner = "Core", status = "New" },
}

return Model
