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
t.assertEqual(Navigation.page("cleanup").title, "Clean Up", "a page may be titled differently from its sidebar row")

-- The Overview leads with its chart and the Folder Map with the open folder.
local OWN_HEADER = {overview = true, folder = true}
local LIST_PAGES = {"largest", "files", "duplicates", "cleanup", "applications", "disks", "xcode", "projects",
	"developer", "music", "video", "photography", "design", "studio3d", "games"}
local listPage = {}
for _, id in ipairs(LIST_PAGES) do listPage[id] = true end

local origin
for _, row in ipairs(Navigation.destinations) do
	if row.id and not OWN_HEADER[row.id] then
		app:show(row.id)
		t.assertEqual(app.destination, row.id, row.id .. " opens")
		local refs = app.page.refs
		t.assertEqual(refs.pageTitle.text, row.title or row.name, row.id .. " is titled as its sidebar row")
		if listPage[row.id] then
			t.assertEqual(app.page.template.path, "apps/diskmap/views/Page.etlua", row.id .. " is the shared list page")
			t.expect(refs.page ~= nil and refs.pageContent ~= nil, row.id .. " is one scrolling page")
			bridge._flushLayout()
			-- AppKit measures from the bottom, so the top inset is what is left
			-- above the header in the page's content.
			local frame, content = refs.pageHeader.frame, refs.pageContent.frame
			local inset = {x = frame.origin.x, top = content.size.height - frame.origin.y - frame.size.height}
			origin = origin or inset
			t.assertEqual(inset.x, origin.x, row.id .. " header starts at the shared leading edge")
			t.assertEqual(inset.top, origin.top, row.id .. " header starts at the shared top edge")
		end
	end
end

-- A page disposed while it waits for a measurement ignores the answer.
local xcode = app.pages.xcode
app:show("xcode")
local generation = xcode.generation
app:show("overview")
t.expect(xcode.generation ~= generation and xcode.template == nil and xcode.refs == nil, "leaving a page ends its visit")

-- Filters sit in one place with one ref on every page that has them.
for _, id in ipairs({"files", "applications", "projects"}) do
	app:show(id)
	t.assertEqual(app.page.refs.filter.className, "NSSegmentedControl", id .. " filters with a segmented control")
end

os.exit(t.summary() and 0 or 1)
