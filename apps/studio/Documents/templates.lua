-- The templates a new project starts from, in the order the New Project
-- sheet lists them. `path` is the template's folder under Documents/; its
-- project.lua lists the files a new project copies. Game templates carry an
-- AGENTS.md that Studio's agent reads before changing the game.
return {
	{id = "StarterApp", title = "Blank App", path = "StarterApp"},
	{id = "HabitTracker", title = "Habit Tracker", path = "HabitTracker"},
	{id = "Platformer", title = "3-D Platformer", path = "Games/Platformer"},
	{id = "Racing", title = "Racing", path = "Games/Racing"},
}
