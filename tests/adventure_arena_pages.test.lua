_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Manifest = require("data.manifest")
local Routes = require("data.routes")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Controller = require("apps.adventure-arena.Controller")
local Session = require("apps.adventure-arena.models.Session")

-- Every page of the manifest has a route with a view that exists.
local manifest = Manifest.load("apps/adventure-arena/app.xml")
local routes = require("apps.adventure-arena.routes")
for _, entry in ipairs(manifest.order) do
	local route = Routes.find(routes, entry)
	local file = io.open("apps/adventure-arena/views/" .. route.view .. ".etlua")
	t.expect(file ~= nil, "page " .. entry.id .. " draws an existing view")
	if file then file:close() end
end

-- Pages and flows are plain Lua: they never reach for the native module.
local function source(path)
	local file = assert(io.open(path))
	local text = file:read("a")
	file:close()
	return text
end
for _, path in ipairs({ "pages/Discover", "pages/Bookshelf", "pages/Search", "pages/Settings", "pages/Detail",
	"pages/Collection", "flows/Opening" }) do
	local text = source("apps/adventure-arena/" .. path .. ".lua")
	t.expect(not text:find('require%("ns"%)') and not text:find("ns%.%u"), path .. " does not touch ns")
end

local function memoryStore() local value return { load = function() return value end, save = function(v) value = v end } end
local controller = Controller.new {
	sessionModel = Session.new(), ns = ns, after = function() end,
	documents = { saves = memoryStore(), reading = memoryStore() },
}
controller:home()
local pages = controller.pages

-- A page is a request: the route answers the data, the actions are its methods.
local discover = pages:data("discover")
t.assertEqual(#discover.featured, 3, "Discover asks the catalog for its featured stories")
t.expect(type(discover.actions.featured_1) == "function", "a row action named by the data is an action of the view")
t.expect(type(discover.actions.openCreate) == "function", "a route method is an action of the view")
t.assertEqual(discover.handlers, nil, "handlers are folded into actions")

-- Search keeps its query on the page and answers again.
local search = pages:data("search")
search.actions.search("  zork ")
t.assertEqual(pages:page("search").query, "zork", "the search page keeps the trimmed query")
t.assertEqual(#pages:data("search").results, #Adventures:search("zork"), "results follow the query")

-- Opening a story from a page pushes the detail page on the stack the tap names.
local game = Adventures:all()[1]
t.expect(pages:page("discover"):flow("Opening"):game(game.id, "library"), "a known story opens")
t.assertEqual(controller.navigation.depth, 2, "the detail page is pushed")
t.expect(not pages:page("discover"):flow("Opening"):game("missing", "library"), "an unknown story is refused")
t.assertEqual(controller.navigation.depth, 2, "a refused story leaves navigation alone")
local collection = Adventures:shelves()[1].title
t.expect(pages:page("discover"):flow("Opening"):collection(collection, "library"), "a collection opens")
t.expect(not pages:page("discover"):flow("Opening"):collection("Nothing", "library"), "an empty collection is refused")
t.assertEqual(controller.navigation.depth, 3, "the collection page is pushed")

os.exit(t.summary() and 0 or 1)
