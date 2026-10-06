_G.__headless = true
-- Back and Forward follow locations as a browser follows URLs: a page's
-- argument and its moves within the page are visits, and returning to one
-- shows the page as it was.
local t = require("TestKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Provider = require("apps.diskmap.services.Provider")

local service = Mock.new()
local folderScans = 0
local scanFolder = service.scanFolder
service.scanFolder = function(...) folderScans = folderScans + 1; return scanFolder(...) end
local app = Controller.new(service)
local window = app:createWindow()
local nav = app.navigation
local function history() return table.concat(nav.history, " ") end

t.assertEqual(app:location(), "/overview", "the window opens on the overview")
app:show("help", {topic = "shortcuts"})
t.assertEqual(app:location(), "/help/shortcuts", "a page's argument is in its location")
app:show("files", {filter = "Installers & archives"})
app:show("map", {focus = "developer"})
app.page.actions.up()
t.assertEqual(history(), "/overview /help/shortcuts /files/Installers%20%26%20archives /map/developer /map",
	"moving within a page is a visit too")

nav:back()
t.assertEqual(app:location(), "/map/developer", "Back returns inside the map")
t.assertEqual(app.env:page("map").focusId, "developer", "with the group focused again")
nav:back()
t.assertEqual(app.destination, "files", "Back returns to the previous page")
t.assertEqual(app:location(), "/files/Installers%20%26%20archives", "on the filter it showed")
nav:back()
t.assertEqual(app.env:page("help").opened, "shortcuts", "Back reopens the topic that was open")
t.expect(nav:canGoForward(), "Forward is possible after Back")
nav:forward()
t.assertEqual(app:location(), "/files/Installers%20%26%20archives", "Forward returns where Back left")
t.assertEqual(#nav.history, 5, "Back and Forward add no visits")

app:go("/applications/Most%20data")
t.assertEqual(app.env:page("applications").filterIndex, 3, "a location opens its page on its argument")
t.expect(not nav:canGoForward(), "a new visit drops the visits ahead, as in a browser")
t.assertEqual(history(), "/overview /help/shortcuts /files/Installers%20%26%20archives /applications/Most%20data",
	"the dropped visits are gone")

-- Showing the page and argument already showing is not a visit.
local count = #nav.history
app:show("applications", {filter = "Most data"})
t.assertEqual(#nav.history, count, "the same location is one visit")

-- Inside a measured folder, Back looks out again without measuring again.
app:show("folder", {path = "/"})
local folder = app.env:page("folder")
local child
for _, node in ipairs(folder.tree.root.children or {}) do if node.directory then child = node.path; break end end
t.expect(child ~= nil, "the mock disk has a folder to look inside")
local scans = folderScans
app.page.actions.drill(child)
t.assertEqual(app:location(), "/folder//?focus=" .. child:gsub("/", "%%2F"), "looking inside is a location")
nav:back()
t.assertEqual(folder.focusPath, "/", "Back looks out to the folder measured")
t.assertEqual(folderScans, scans, "without measuring it again")

-- --page takes a location; a bare id is that page.
t.assertEqual(Provider.launch({"--mock", "--page=files"}).page, "/files", "a page id is its location")
t.assertEqual(Provider.launch({"--mock", "--page=/help/shortcuts"}).page, "/help/shortcuts", "--page takes a location")
t.assertThrows(function() Provider.launch({"--mock", "--page=/overview/x"}) end, "a launch location is checked")

app.env.scan:dispose(); window:close()
os.exit(t.summary() and 0 or 1)
