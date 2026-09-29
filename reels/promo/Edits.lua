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
		edits = {
			{ patch = "todo-1-group-completed", prompt = "Group completed tasks.",
				reply = "Open tasks come first now; finished ones collect in their own Completed section." },
			{ patch = "todo-2-progress", prompt = "Add progress at the top.",
				reply = "Added a progress card above the list: tasks done today and a bar." },
			{ patch = "todo-3-filter", prompt = "Add a filter.",
				reply = "Added a segmented filter: All, Open and Flagged." },
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
