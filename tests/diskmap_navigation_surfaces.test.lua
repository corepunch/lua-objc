_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Contract = require("apps.diskmap.services.Contract")
local Controller = require("apps.diskmap.Controller")

local service = Mock.new()
local app = Controller.new(service)
app:createWindow()
local sidebar = app.navigation.refs.sidebar
t.assertEqual(bridge._tableCell(sidebar, 0, 0).textField.stringValue, "Overview", "the sidebar starts with Overview")
t.expect(app.env.watchlist == nil and app.env.model.watchSizes == nil and app.env.model.watchlist == nil, "navigation creates no location tracking state")
t.expect(Contract.members.loadWatchlist == nil and Contract.members.saveWatchlist == nil, "providers need no location tracking persistence")
t.expect(service.loadWatchlist == nil and service.saveWatchlist == nil, "the mock provider exposes no location tracking persistence")

local function noPinActions(items, context)
	for _, item in ipairs(items) do
		t.expect(not (item.title or ""):find("Favorites", 1, true), context .. " has no pin action")
	end
end
noPinActions(app.env.rowActions:resource("derived"), "resource menu")
noPinActions(app.env.rowActions:folder({path = service.home .. "/Library/Developer", name = "Developer", directory = true}), "folder menu")

app:show("map", {focus = "xcode"})
app.page.request:chartSelect("derived")
t.expect(app.page.refs.mapFavorite == nil, "the map has no pin button")
t.expect(app.page.refs.mapOpen.enabled and app.page.refs.mapInspect.enabled, "selected locations still open or inspect their folder")
ns._invokeAction(app.page.refs.mapOpen)
t.assertEqual(app.destination, "xcode", "Derived Data still opens its dedicated page")
app.navigation:back()
t.assertEqual(app.destination, "map", "Back returns to Storage Map")
app.navigation:forward()
t.assertEqual(app.destination, "xcode", "Forward restores the dedicated page")

app:show("largest")
app.page.request:select(nil, nil, {id = "derived", path = service.home .. "/Library/Developer/Xcode/DerivedData", name = "Xcode DerivedData"})
app:updateRows()
t.expect(app.page.refs.favoriteSelection == nil, "selected Largest Locations has no pin button")
t.expect(app.page.refs.openSelection ~= nil and app.page.refs.inspectSelection ~= nil, "Largest Locations keeps its destination actions")
app:openFolder(service.home .. "/Library/Developer")
t.expect(app.page.refs.favoriteFolder == nil, "Folder Map has no pin button")
t.expect(app.page.refs.folderOpen ~= nil, "Folder Map retains its selected-item action")

app:open("xcode-app")
local sdks = app.env.sdks
t.expect(sdks.sheet ~= nil and sdks.refs.rows ~= nil, "an Xcode installation still opens the SDK sheet")
t.expect(sdks.refs.favorite == nil, "the SDK sheet has no pin button")
sdks:close()
app:show("overview")
t.assertEqual(sidebar.documentView.selectedRow, app.navigation:index("overview"), "native selection returns to Overview")
os.exit(t.summary() and 0 or 1)
