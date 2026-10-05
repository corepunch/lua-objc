_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

local service = Mock.new()
local app = Controller.new(service)
app:createWindow()
local navigation, sidebar = app.navigation, app.navigation.refs.sidebar
local initialRows = sidebar.rowCount
local function favorite(entry) return app.env.watchlist:toggle(entry) end
local function visit(key) sidebar:selectRow(navigation:index("watched:" .. key)) end
local function menuItem(items, title)
	for _, item in ipairs(items) do if item.title == title then return item end end
end

-- Favorites use the persisted watchlist; adding one does not leave the page.
t.expect(favorite({kind = "resource", id = "derived"}), "Derived Data can be favorited")
t.assertEqual(app.destination, "overview", "pinning keeps the current page")
t.assertEqual(sidebar.rowCount, initialRows + 2, "one favorite creates one section and one shortcut")
t.assertEqual(bridge._tableCell(sidebar, 0, 0).textField.stringValue, "Favorites", "the sidebar names Favorites")
t.assertEqual(#service.watchlist, 1, "favorites save immediately")
app:search("largest", "Xcode")
visit("resource:derived")
t.assertEqual(app.destination, "xcode", "Derived Data opens its dedicated Xcode page in one click")
t.assertEqual(app.query, "", "a favorite page arrival clears the previous page's search")
t.assertEqual(navigation.current, "watched:resource:derived", "the favorite remains selected")
t.assertEqual(sidebar.documentView.selectedRow, navigation:index(navigation.current), "native selection stays on the shortcut")

-- Installations reopen their SDK sheet, rather than the parent Developer sheet.
app:open("xcode-app")
local sdks = app.env.sdks
t.expect(sdks.refs.favorite ~= nil, "the SDK sheet visibly offers a favorite action")
ns._invokeAction(sdks.refs.favorite)
t.assertEqual(sdks.refs.favorite.title, "Remove from Favorites", "the button updates after saving")
t.expect(app.env.watchlist:find("resource:xcode-app") ~= nil, "the installation's exact id is saved")
sdks:close()
app:show("overview")
visit("resource:xcode-app")
t.expect(sdks.sheet ~= nil, "one favorite click opens the SDK sheet")
t.assertEqual(sdks.root, "/Applications/Xcode.app", "the saved installation is restored")
t.expect(app.env.management.sheet == nil, "SDK arrival leaves no category sheet open")
sdks:close()

-- Individual SDKs are folders, independently selectable from their installation.
local sdkPath = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
local item = menuItem(sdks:rowMenu(nil, nil, {path = sdkPath, name = "iPhoneOS"}), "Add to Favorites")
t.expect(item ~= nil, "an individual SDK menu can pin its folder")
item.action()
visit("folder:" .. sdkPath)
t.assertEqual(app.destination, "folder", "the SDK folder opens Folder Map")
t.assertEqual(app.env:page("folder").path, sdkPath, "the shortcut keeps the exact SDK path")

-- Two arbitrary folders have distinct history tokens and survive a restart.
local a, b = service.home .. "/Library/Developer", service.home .. "/Downloads"
favorite({kind = "folder", path = a, name = "Developer"})
favorite({kind = "folder", path = b, name = "Downloads"})
visit("folder:" .. a)
visit("folder:" .. b)
t.assertEqual(app.env:page("folder").path, b, "the second favorite opens its own path")
local count = #navigation.history
navigation:back()
t.assertEqual(app.env:page("folder").path, a, "Back restores the previous favorite's folder")
t.assertEqual(#navigation.history, count, "history restoration adds no visit")
navigation:forward()
t.assertEqual(app.env:page("folder").path, b, "Forward restores the next favorite's folder")
local historyPosition = navigation.position
app:updateRows()
t.assertEqual(navigation.position, historyPosition, "refreshing badges does not navigate")
t.assertEqual(navigation.current, "watched:folder:" .. b, "refresh preserves the shortcut selection")
t.assertEqual(app.page.refs.favoriteFolder.title, "Remove from Favorites", "Folder Map exposes its current folder's favorite state")

local second = Controller.new(service)
second:createWindow()
t.expect(second.navigation:index("watched:resource:derived") ~= nil, "Derived Data returns after restart")
t.expect(second.navigation:index("watched:resource:xcode-app") ~= nil, "the SDK installation returns after restart")
t.expect(second.navigation:index("watched:folder:" .. sdkPath) ~= nil, "the individual SDK returns after restart")
second:openFavorite("folder:" .. a)
t.assertEqual(second.env:page("folder").path, a, "a restarted shortcut keeps its exact path")

-- Tracking remains available locally; removing a shortcut preserves other favorites.
local key = "folder:" .. a
local items = second:favoriteMenu({id = "watched:" .. key})
menuItem(items, "View Size Changes").action()
t.assertEqual(second.destination, "watched", "the sidebar menu opens size changes")
t.assertEqual(second.env:page("watched").key, key, "size changes belong to the chosen folder")
local refs = second.page.refs
refs.page.size = ns.Size(674, 480)
refs.page:layout(674)
t.expect(refs.pageTitle.frame.size.width >= refs.pageTitle.fittingSize.width, "the favorite's name fits at the minimum content width")
for _, id in ipairs({"reveal", "unwatch"}) do
	t.expect(refs[id].frame.size.width >= refs[id].fittingSize.width, "the favorite action fits at minimum width: " .. id)
end
menuItem(items, "Remove from Favorites").action()
t.expect(second.env.watchlist:find(key) == nil, "removal forgets this shortcut")
t.expect(second.env.watchlist:find("resource:derived") ~= nil, "removal leaves other shortcuts unchanged")
t.assertEqual(second.navigation:index("watched:" .. key), nil, "the removed shortcut disappears")
local destination = second.destination
second:openFavorite(key)
t.assertEqual(second.destination, destination, "opening a removed shortcut changes nothing")
t.assertEqual(#second:favoriteMenu({id = "overview"}), 0, "ordinary navigation has no favorite menu")

-- Visible actions pin the selected token, never the pointer's transient target.
second:show("map", {focus = "xcode"})
local map = second.env:page("map")
t.expect(not second.page.refs.mapFavorite.enabled, "the favorite button is disabled without a selection")
map:chartSelect("archives")
map:chartHover("derived")
ns._invokeAction(second.page.refs.mapFavorite)
t.expect(second.env.watchlist:find("resource:archives") ~= nil, "the visible action pins the selected location")
t.assertEqual(second.page.refs.mapFavorite.title, "Remove from Favorites", "map selection reflects the saved favorite")
second:show("largest")
second.env:page("largest"):select(nil, nil, {id = "archives"})
second:updateRows()
t.assertEqual(second.page.refs.favoriteSelection.title, "Remove from Favorites", "Largest Locations shares the same favorite state")
ns._invokeAction(second.page.refs.favoriteSelection)
t.expect(second.env.watchlist:find("resource:archives") == nil, "Largest Locations can remove the selected favorite")

local missing = "/Users/test/Missing SDK with a very long name"
second.env.watchlist:toggle({kind = "folder", path = missing})
second.env.watchlist.list:record("folder:" .. missing, nil, false)
second:updateRows()
local missingRow
for _, row in ipairs(second.navigation:rows()) do if row.id == "watched:folder:" .. missing then missingRow = row end end
t.assertEqual(missingRow.badge, "Missing", "missing folders stay visible with an honest badge")
t.expect(missingRow.help:find(missing, 1, true) ~= nil, "long favorite names retain the full path in native help")
second:show("watched", {key = "folder:" .. missing})
t.expect(second.page.refs.reveal == nil, "a missing favorite offers no Finder action")
t.expect(second.page.refs.unwatch ~= nil, "a missing favorite can still be removed")

local firstMenu = app:favoriteMenu({id = "watched:resource:derived"})
second:show("overview")
menuItem(firstMenu, "Remove from Favorites").action()
t.expect(app.env.watchlist:find("resource:derived") == nil, "a menu retained by the first window removes from its own store")
second:show("overview")
t.expect(second.env.watchlist:find("resource:derived") ~= nil, "another window's favorites remain unchanged")

os.exit(t.summary() and 0 or 1)
