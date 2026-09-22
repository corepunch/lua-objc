local Model = {}

function Model.presentation()
	return {
		status = "Ready",
		prompt = "Create a simple habit tracker app like this. Use a clean modern design with a nice illustration. It should store data locally and have 3 tabs: Today, Stats, Settings.",
		response = "I’ll create a habit tracker app with a clean design, local storage, and the requested tabs. I’ll set up the project structure and implement the main screens.",
		files = {"HabitPal", "Info.plist", "App.lua", "Views/", "Models/", "Assets/"},
		suggestions = {"Add a feature", "Fix a bug", "Improve UI"},
		tabs = {"Preview", "Logs"},
	}
end

return Model
