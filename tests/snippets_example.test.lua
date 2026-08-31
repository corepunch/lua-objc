local t = require("TestKit")
local Model = require("examples.snippets.Model")

Model.initialize()

local byFolder = Model.filterSnippets("ui", "", false, false)
t.expect(type(byFolder) == "table" and #byFolder > 0, "folder filtering returns snippets")

local byTag = Model.filterSnippets("all", "button", false, false)
t.expect(#byTag >= 1, "query search matches snippet content")

local recentsBefore = #Model.recentSnippets()
t.expect(type(recentsBefore) == "number", "recent list exists")

local favoriteBefore = Model.isFavorite("primary-button")
Model.toggleFavorite("primary-button")
t.expect(Model.isFavorite("primary-button") ~= favoriteBefore, "favorite toggles state")

Model.recordRecent("primary-button")
t.expect(Model.recentSnippets()[1] == "primary-button", "recent snippets store item order")

local persisted = Model.loadState()
t.expect(type(persisted) == "table", "state can be loaded from disk")

os.exit(t.summary() and 0 or 1)
