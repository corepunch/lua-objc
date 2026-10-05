_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Routes = require("data.routes")
local Scans = require("apps.diskmap.models.Scans")
local function routePage(id, app) return Routes.page(require("apps.diskmap.routes")[id], {id = id}, app, "apps.diskmap") end

-- Overview, Map and Folder are models drawn by the framework's page
-- controller: no controller class remains for them.
for _, name in ipairs({"OverviewController", "MapController", "FolderController"}) do
	t.expect(not pcall(require, "apps.diskmap.controllers." .. name), name .. " is gone")
end

local app = Controller.new(Mock.new())
app:createWindow()
local _, ids = Scans:plan()

-- While the scan runs the pages draw their empty state; the scan's end draws them again.
Scans:begin(ids)
app:updateRows()
t.assertEqual(app.page.refs.results, nil, "a running scan leaves the Overview without a category list")
t.expect(app.page.refs.legendExplanation ~= nil and app.page.refs.legend == nil, "and without a legend")
t.expect(app.page.refs.cleanUp == nil, "and without a cleanup offer")
app:show("map")
t.expect(app.page.refs.mapEmpty ~= nil, "the Map says nothing is measured yet")
t.assertEqual(app.page.refs.mapList.rowCount, 0, "and lists nothing")
app.env.scan:start()
t.expect(app.page.refs.mapEmpty == nil and app.page.refs.mapList.rowCount > 0, "the Map is drawn when the scan has finished")

-- Map: focus by breadcrumb position, up, styles.
local map = app.env:page("map")
app.page.actions.chartSelect("developer", 1)
t.assertEqual(map.focusId, "developer", "a group looks inside")
t.assertEqual(app.page.refs.mapSummary.text:find("Developer", 1, true), 1, "the summary names the focus")
app.page.actions.focus_1()
t.assertEqual(map.focusId, "", "the first breadcrumb step goes back to the whole map")
app.page.actions.chartSelect("developer", 1)
app.page.actions.up()
t.assertEqual(map.focusId, "", "up leaves the group")
app.page.actions.chartSelect("applications#other", 1)
t.assertEqual(map.focusId, "", "a folded remainder cannot be focused")
t.assertThrows(function() map:setStyle("hexagons") end, "an unknown map style is an error")
t.assertEqual(map.style, "rings", "a rejected style leaves the chart alone")
t.assertEqual(routePage("map", {mapStyle = "rectangles"}).style, "rectangles", "the services pick the first style")

-- Hovering only points: it draws nothing again and clears with the pointer.
local list = app.page.refs.mapList
app.page.actions.chartHover("developer")
t.assertEqual(app.page.refs.mapList, list, "pointing keeps the list")
app.page.actions.chartHover(nil)
t.assertEqual(map.selectedId, nil, "leaving the chart clears the token")
t.assertEqual(app.page.refs.mapHover.text, map.hover, "and the line under it")

-- Folder: states of the page.
local folder = app.env:page("folder")
app:show("folder")
t.expect(app.page.refs.folderEmpty ~= nil and app:badges().folder == nil, "an unopened folder invites a drop and has no badge")
app.page.actions.pickStyle(1)
t.assertEqual(folder.style, "rectangles", "the style picker changes the style")
app.page.actions.pickStyle(0)
t.assertThrows(function() folder:pickStyle(7) end, "an unknown folder map style is an error")
folder:pickColoring(99)
t.assertEqual(folder.coloring, "folders", "an unknown coloring changes nothing")
t.assertEqual(folder:open("relative/path"), false, "only absolute paths open")
app:openFolder("/Nowhere")
t.expect(app.page.refs.folderFailed ~= nil, "a folder that cannot be read says so")
app.page.actions.stop()
t.expect(folder.loading == nil, "stopping leaves nothing loading")
t.assertEqual(routePage("folder", {model = app.env.model, service = app.env.service}).path, nil, "a new page has no folder")
os.exit(t.summary() and 0 or 1)
