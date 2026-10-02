_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.models.Session")
local Controller = require("apps.adventure-arena.Controller")

local renderFile, button = xml.renderFile, ns.Button
local rendered, callbacks = {}, {}
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
local function click(ref)
	local callback = callbacks[rendered.refs[ref]]
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
t.expect(rendered.refs.emptyCatalog ~= nil, "an empty catalog still has a named empty state")
t.expect(rendered.refs.openCreate ~= nil, "the empty catalog names the next tap")
t.expect(empty:selectTab("missing") == false, "unknown tabs are rejected")
t.expect(empty:selectTab("create") == true, "selectTab accepts a tab name without a window")
t.assertEqual(empty.selectedTab, 2, "Create is the third tab")

local windowed = make()
windowed:createWindow()
t.expect(windowed.tabs ~= nil, "createWindow keeps the native tab view")
t.expect(rendered.refs.emptyCatalog ~= nil, "the windowed empty catalog is still composed")
t.expect(rendered.refs.openCreate ~= nil, "the windowed empty catalog still has a CTA")
click("openCreate")
t.assertEqual(windowed.selectedTab, 2, "Write an Adventure selects the Create tab")
t.assertEqual(windowed.navigation, windowed.navigations.create, "Create owns navigation after the empty-catalog CTA")

windowed:selectTab("bookshelf")
t.expect(rendered.refs.emptyBookshelf ~= nil or windowed.bookshelf ~= nil,
	"the Library tab mounts even when nothing is saved")
if windowed.bookshelf then
	local _, shelfRefs = windowed.bookshelf:update(windowed.library:bookshelf())
	rendered.refs = shelfRefs
	t.expect(shelfRefs.emptyBookshelf ~= nil, "an empty library names its empty state")
	t.expect(shelfRefs.browseDiscover ~= nil, "an empty library names Browse Discover")
	local browse = callbacks[shelfRefs.browseDiscover]
	t.expect(type(browse) == "function", "Browse Discover is bound")
	if browse then browse() end
	t.assertEqual(windowed.selectedTab, 0, "Browse Discover returns to Discover")
	t.assertEqual(windowed.navigation, windowed.navigations.library, "Discover owns navigation after Browse Discover")
end

ns.Button, xml.renderFile = button, renderFile
os.exit(t.summary() and 0 or 1)
