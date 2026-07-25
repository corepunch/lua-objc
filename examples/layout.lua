local ui = require("luaui")

local navigation = ui.List {
	width = 170,
	height = 280,
	header = false,
	flex_basis = 170,
	flex_grow = 1,
	flex_shrink = 1,
	min_width = 130,
	max_width = 240,
	columns = {
		{ id = "section", title = "Section" },
	},
	data = {
		{ section = "Overview" },
		{ section = "Activity" },
		{ section = "Reports" },
		{ section = "Settings" },
	},
}

local content = ui.List {
	width = 380,
	height = 280,
	flex_basis = 300,
	flex_grow = 2,
	flex_shrink = 1,
	min_width = 260,
	columns = {
		{ id = "item", title = "Item", width = 120 },
		{ id = "owner", title = "Owner", width = 75 },
		{ id = "status", title = "Status", width = 65 },
	},
	data = {
		{ item = "Declarative layout", owner = "Core", status = "Ready" },
		{ item = "Native tables", owner = "AppKit", status = "Ready" },
		{ item = "Measurement pass", owner = "Core", status = "New" },
		{ item = "Flexible sizing", owner = "Core", status = "New" },
	},
}

ui.Window {
	title = "Flexible Layout",
	width = 680,
	height = 420,
	ui.VStack {
		padding = 20,
		alignment = "leading",
		ui.Title "Measured, then placed",
		ui.Text {
			"Panels grow 1:2, shrink from their measured basis, and respect minimum widths.",
			flex_shrink = 1,
		},
		ui.Separator(),
		ui.HStack {
			flex_grow = 1,
			alignment = "top",
			navigation,
			content,
		},
		ui.HStack {
			ui.Text "Resize the window to exercise the constraints.",
			ui.Spacer(),
			ui.Button { title = "Done" },
		},
	}
}
