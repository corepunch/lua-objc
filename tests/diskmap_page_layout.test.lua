_G.__headless = true
local t = require("TestKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Navigation = require("apps.diskmap.controllers.NavigationController")

-- Every page is headed by its sidebar row: one table names the page in the
-- sidebar, the Go menu and the page itself, so they cannot disagree. Pages
-- that rank storage in lists share one template, so their headers, tiles and
-- sections start at the same place.
local app = Controller.new(Mock.new())
app:createWindow()

local ids = {}
for _, row in ipairs(Navigation.destinations) do
	if row.id then
		t.expect(not ids[row.id], "destination ids are unique: " .. row.id); ids[row.id] = true
		t.expect(type(row.icon) == "string" and type(row.color) == "string", row.id .. " has an icon and a color for its header")
		t.assertEqual(Navigation.page(row.id), row, row.id .. " is found by id")
	end
end
t.expect(Navigation.page("nowhere") == nil, "an unknown id names no page")
t.assertEqual(Navigation.page("cleanup").name, "Clean Up", "the sidebar row, the page and the toolbar share one name")
t.assertEqual(Navigation.page("cleanup").title, nil, "with no second title to drift")

-- Every page is titled in the window title by its sidebar row, and starts
-- with its content: no page draws a heading of its own. Breakdown pages that
-- show one level of something are titled by that level instead.
local OWN_TITLE = {overview = true, folder = true}
local LIST_PAGES = {"largest", "files", "duplicates", "cleanup", "applications", "disks", "xcode", "projects",
	"everyday", "developer", "music", "video", "photography", "design", "studio3d", "games"}
local listPage = {}
for _, id in ipairs(LIST_PAGES) do listPage[id] = true end

local window = app.window
local origin
for _, row in ipairs(Navigation.destinations) do
	if row.id then
		app:show(row.id)
		t.assertEqual(app.destination, row.id, row.id .. " opens")
		local refs = app.page.refs
		t.expect(refs.pageHeader == nil and refs.pageTitle == nil, row.id .. " has no heading of its own")
		if not OWN_TITLE[row.id] then t.assertEqual(window.title, row.title or row.name, row.id .. " is titled as its sidebar row") end
		if listPage[row.id] then
			t.assertEqual(app.page.template.path, "apps/diskmap/views/pages/Page.etlua", row.id .. " is the shared list page")
			t.expect(refs.page ~= nil and refs.pageContent ~= nil, row.id .. " is one scrolling page")
			bridge._flushLayout()
			local frame = refs.pageContent.frameInWindow
			origin = origin or frame.origin
			t.assertEqual(frame.origin.x, origin.x, row.id .. " content starts at the shared leading edge")
		end
	end
end

local cardOrigin
for _, id in ipairs({"overview", "map", "kinds", "folder"}) do
	app:show(id, id == "folder" and {path = app.env.model.home} or nil)
	t.assertEqual(app.page.template.path, "apps/diskmap/views/pages/Breakdown.etlua", id .. " is the shared breakdown page")
	local refs = app.page.refs
	if refs.breakdown then
		bridge._flushLayout()
		local frame = refs.breakdown.frameInWindow
		cardOrigin = cardOrigin or frame.origin
		t.assertEqual(frame.origin.x, cardOrigin.x, id .. " card starts at the shared leading edge")
	end
end

-- A page disposed while it waits for a measurement ignores the answer.
app:show("xcode")
local xcode = app.page
local model = xcode.request
local stock = model.stock
app:show("overview")
t.expect(model.stock == stock and xcode.template == nil and xcode.refs == nil, "leaving a page ends its visit")

-- Filters sit in one place with one ref on every page that has them.
for _, id in ipairs({"files", "applications", "projects"}) do
	app:show(id)
	t.assertEqual(app.page.refs.filter.className, "NSSegmentedControl", id .. " filters with a segmented control")
end

os.exit(t.summary() and 0 or 1)
