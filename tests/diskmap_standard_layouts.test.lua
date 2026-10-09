_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Marks = require("apps.diskmap.models.Marks")
local function source(path)
	local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text
end

-- Every screen chooses one shell. Geometry belongs to the shells, so a
-- new screen cannot silently reintroduce a fixed map height or footer.
local shells = {ContentPage = true, TablePage = true}
for _, name in ipairs({"Basket", "Breakdown", "Filesystem", "History", "Onboarding", "Page", "Sdks", "Settings", "Simulators", "SnapshotChanges", "Topics", "Tour", "Updates", "Worktrees"}) do
	local text = source("apps/diskmap/views/pages/" .. name .. ".etlua")
	local count = 0
	for shell in text:gmatch("<(%w+Page) ") do t.expect(shells[shell], name .. " uses a standard shell"); count = count + 1 end
	t.assertEqual(count, 1, name .. " has exactly one page shell")
	t.expect(not text:find('id="pageContent"', 1, true), name .. " delegates the content stack to its shell")
	t.expect(not text:find("PageFrame", 1, true), name .. " has no old layout path")
end
local host = source("apps/diskmap/views/layouts/Content.etlua")
t.expect(not host:find("collector", 1, true) and not host:find("Review", 1, true), "the window content has no review footer")
local breakdownPage = source("apps/diskmap/views/pages/Breakdown.etlua")
t.expect(not breakdownPage:find("ringsHeight", 1, true) and not breakdownPage:find("chartHeight", 1, true), "breakdown pages have no content-height calculation")

local app = Controller.new(Mock.new({showcase = true}))
local window = app:createWindow()
for _, size in ipairs({{950, 580}, {1280, 800}, {1900, 1000}}) do
	window.size = ns.Size(size[1], size[2])
	for _, id in ipairs({"history", "snapshotChanges", "sdks"}) do
		app:show(id, id == "sdks" and {id = "xcode-app"} or nil)
		bridge._flushLayout()
		local refs = app.page.refs
		local list = refs.entries or refs.changes or refs.rows
		t.expect(not list.scrollDisabled, id .. " uses native table scrolling")
		if not list.hidden then
			local frame, content = list.frameInWindow, refs.pageContent.frameInWindow
			t.expect(math.abs(frame.origin.y - content.origin.y) < 1, id .. " table reaches the bottom inset")
		end
	end
end

-- Flagging does not change the window's usable content area or repeat the
-- toolbar badge in a title/status bar. Review still accepts external files.
app:show("map", {focus = "system-data"})
bridge._flushLayout()
local height = app.content.size.height
app.env.basket:toggle({path = "/Users/appleseed/Downloads/layout-test.zip", bytes = 20})
bridge._flushLayout()
t.assertEqual(app.content.size.height, height, "flagging reserves no bottom bar")
t.assertEqual(app.collector, nil, "there is no collector view")
t.assertEqual(app.collectorController, nil, "there is no collector controller")
t.expect(not window.subtitle:find("flagged", 1, true), "the title does not duplicate the Flagged badge")
app:openReview()
t.expect(bridge._dropFiles(app.page.refs.pageContent, {"/System"}), "Review accepts a dropped location")
t.expect(Marks:find("/System").reviewOnly, "protected locations remain inspection-only")
Marks:clear(); app:basketChanged()
window:close()
os.exit(t.summary() and 0 or 1)
