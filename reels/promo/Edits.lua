-- The agent edits the promo shows, in order per app. Each is a real diff in
-- edits/ against the app as it is in the repository: the repository holds
-- every app in its final state, and version k of an app is that state with
-- edits k+1…n reverse-applied. So version 0 is the app before the agent
-- touched it, and the last version is the app as it ships. The capture
-- pipeline builds each version, and tests/promo_reel.test.lua checks that
-- every patch still reverse-applies, so the edits cannot rot as the apps
-- change.
return {
	todo = {
		dir = "demo/todo",
		-- How Lua Studio lists the project.
		title = "Tasks", icon = "checklist",
		files = { "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua", "views/Sidebar.etlua",
			"views/Content.etlua", "views/TaskRow.etlua" },
		-- States reached by using the app on the phone: version `from` with
		-- its sample data changed. The film keeps them consistent: the task
		-- checked on the iPad's preview stays checked through the filter.
		states = {
			{ name = "checked", from = 2, changes = { "done" } },
			{ name = "filtered", from = 3, changes = { "done" } },
			{ name = "open", from = 3, changes = { "done", "open" } },
		},
		-- The changes, each one text replacement in one file.
		changes = {
			-- The first open task, checked off.
			done = { file = "Model.lua", find = 'project = "launch", due = "11:30", flagged = true}',
				replace = 'project = "launch", due = "11:30", flagged = true, done = true}' },
			-- "Open" chosen in the filter.
			open = { file = "Model.lua", find = "projects = {}, filter = 1}", replace = "projects = {}, filter = 2}" },
		},
		edits = {
			{ patch = "todo-1-group-completed", prompt = "Group completed tasks.",
				reply = "Open tasks come first now; finished ones collect in their own Completed section." },
			{ patch = "todo-2-progress", prompt = "Add progress at the top.",
				reply = "Added a progress card above the list: tasks done today and a bar." },
			{ patch = "todo-3-filter", prompt = "Add a filter.",
				reply = "Filtering lives in the Model, the Controller handles the choice, and the view shows All, Open and Flagged." },
		},
	},
	notes = {
		dir = "demo/notes",
		edits = {
			{ patch = "notes-favorites", prompt = "Add a favorites section.",
				reply = "Starred notes now sit in a Favorites box above the list." },
		},
	},
	ledger = {
		dir = "demo/ledger",
		edits = {
			{ patch = "ledger-weekly", prompt = "Make the chart weekly.",
				reply = "The spending chart now opens by week." },
		},
	},
}
