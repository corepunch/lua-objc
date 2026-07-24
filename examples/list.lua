local ui = require("luaui")

ui.Window {
	title = "Employee Directory",
	width = 640,
	height = 420,
	ui.VStack {
		ui.Text "Employees",
		ui.List {
			width = 620,
			height = 350,
			columns = {
				{ id = "name", title = "Name" },
				{ id = "role", title = "Role" },
				{ id = "dept", title = "Dept" },
			},
			data = {
				{ name = "Alice Chen",    role = "Engineer",   dept = "Core" },
				{ name = "Bob Martinez",  role = "Designer",   dept = "UX" },
				{ name = "Carol Park",    role = "Manager",    dept = "Eng" },
				{ name = "Dave Johnson",  role = "Engineer",   dept = "Core" },
				{ name = "Eve Williams",  role = "Analyst",    dept = "Data" },
				{ name = "Frank Brown",   role = "Intern",     dept = "Eng" },
			}
		}
	}
}
