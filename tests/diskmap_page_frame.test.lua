_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Navigation = require("apps.diskmap.controllers.NavigationController")

-- Every page sits in one frame (components/PageFrame): in a wide window
-- its header is no wider than the readable column and starts at the same
-- leading edge on every page, table pages and maps included.
local FRAME = {width = 960}
local app = Controller.new(Mock.new({showcase = true}))
local window = app:createWindow()
window.size = ns.Size(1900, 1000)

for _, row in ipairs(Navigation.destinations) do
	if row.id then
		app:show(row.id, row.id == "folder" and {path = "/Users/appleseed/Downloads"} or nil)
		bridge._flushLayout()
		local refs = app.page.refs
		t.expect(refs.page ~= nil, row.id .. " has a page frame")
		local header = refs.pageHeader or refs.pageTitle
		if header then
			local frame = header.frameInWindow
			t.expect(frame.size.width <= FRAME.width, row.id .. " is no wider than the readable column")
			-- Centered in what the page shows: beside a legacy scroll bar the
			-- visible area is narrower, so the column moves by half of it.
			local visible = (refs.page.contentView or refs.page).frameInWindow
			t.expect(math.abs(frame.origin.x + frame.size.width / 2 - (visible.origin.x + visible.size.width / 2)) < 0.5,
				row.id .. " is centered in the page")
		end
	end
end

-- The Folder Map's chart pane keeps a gap from its list, as the Storage
-- Map's panes do: a split view's divider is a hairline, not spacing.
app:show("folder", {path = "/Users/appleseed/Downloads"})
bridge._flushLayout()
local refs = app.page.refs
local list, chart = refs.folderList.frameInWindow, refs.folderChartHost.frameInWindow
t.expect(chart.origin.x - (list.origin.x + list.size.width) >= 16, "the folder rings keep a gap from the list")

window:close()
os.exit(t.summary() and 0 or 1)
