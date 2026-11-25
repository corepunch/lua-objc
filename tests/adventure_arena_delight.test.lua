_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Controller = require("apps.adventure-arena.Controller")

local renderFile, button = xml.renderFile, ns.Button
local navigationStack, searchField = ns.NavigationStack, ns.SearchField
local rendered, callbacks, toolbarActions = {}, {}, {}
local searchChanged
ns.NavigationStack = function(props)
	t.assertEqual(props.titleDisplayMode, "inlineLarge", "Discover shares one navigation row with its actions")
	for _, item in ipairs(props.toolbar or {}) do toolbarActions[item.id] = item.action end
	return navigationStack(props)
end
ns.SearchField = function(props)
	searchChanged = props.onChange
	return searchField(props)
end
ns.Button = function(props)
	local view = button(props)
	callbacks[view] = props.action
	return view
end
xml.renderFile = function(...)
	local view, refs = renderFile(...)
	rendered = { view = view, refs = refs }
	return view, refs
end
local function click(refs, ref)
	local callback = callbacks[refs[ref]]
	t.expect(type(callback) == "function", ref .. " has a bound action")
	if callback then callback() end
end
local function memoryStore()
	local value
	return { load = function() return value end, save = function(v) value = v end }
end
local function make(options)
	options = options or {}
	return Controller.new {
		games = options.games or {},
		sessionModel = Session.new(),
		ns = ns,
		documents = { saves = memoryStore(), reading = memoryStore() },
		after = function() end,
	}
end

local empty = make()
empty:home()
local emptyRefs = empty.pages:refs("discover")
t.expect(emptyRefs.emptyCatalog ~= nil, "an empty catalog still has a named empty state")
t.expect(emptyRefs.openCreate ~= nil, "the empty catalog names the next tap")
local windowed = make()
windowed:createWindow()
t.expect(rendered.refs.tabs == nil and rendered.refs.nowReading == nil, "the window has no bottom bar")
local windowedRefs = windowed.pages:refs("discover")
t.expect(windowedRefs.openCreate ~= nil, "the windowed empty catalog still has a CTA")
click(windowedRefs, "openCreate")
t.assertEqual(windowed.navigation.depth, 2, "Write an Adventure opens a page on the catalog stack")
windowed.navigation:pop()

t.expect(type(toolbarActions.catalogSettings) == "function", "Home has a Settings button")
toolbarActions.catalogSettings()
t.expect(windowed.pages:refs("settings").noGamesInProgress ~= nil, "Settings includes Games in Progress")
windowed.navigation:pop()
t.expect(windowed.pages:refs("settings") == nil, "popping Settings unmounts its content")
t.expect(type(toolbarActions.findStories) == "function", "Home has a Search button")
toolbarActions.findStories()
t.expect(rendered.refs.searchField ~= nil, "Search opens with its field")
t.expect(type(searchChanged) == "function", "the search field is bound")
searchChanged("unmatched story")
t.expect(windowed.pages:refs("search").noResults ~= nil, "the search field updates results on the page")
windowed.navigation:pop()
t.assertEqual(windowed.navigation.depth, 1, "Search returns to the same catalog")
ns.NavigationStack, ns.SearchField = navigationStack, searchField

ns.Button, xml.renderFile = button, renderFile
os.exit(t.summary() and 0 or 1)
