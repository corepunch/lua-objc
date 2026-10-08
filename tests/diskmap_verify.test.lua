_G.__headless = true
local t = require("TestKit")
local Marks = require("apps.diskmap.models.Marks")
local Verify = require("apps.diskmap.helpers.Verify")

-- Each marked item is checked again just before it moves (#52).
local home = "/Users/test"
local present = {
	[home .. "/Library/Caches/com.google.Chrome"] = true,
	[home .. "/Library/Caches/com.google.Chrome.helper"] = true,
	[home .. "/Documents/site/node_modules"] = true,
	[home .. "/Documents/site/package.json"] = true,
	[home .. "/Documents/old/node_modules"] = true,
	[home .. "/Library/Containers/com.old.App"] = true,
	[home .. "/Downloads/big.iso"] = true,
}
local inodes = {[home .. "/Downloads/big.iso"] = 7}
local probes = {
	running = {["com.google.Chrome"] = true, ["com.apple.dt.Xcode"] = true},
	exists = function(path) return present[path] == true end,
	identity = function(path) return present[path] and {inode = inodes[path] or 1, device = 1} or nil end,
	appPath = function(id)
		if id == "com.apple.dt.Xcode" then return "/Applications/Xcode.app" end
		if id == "com.old.App" then return "/Volumes/Apps/Old App.app" end
		return nil
	end,
}
local function check(item, resource) return Verify.check(item, resource, home, probes) end

t.assertEqual(Verify.bundleId(home .. "/Library/Caches/com.google.Chrome/Default"), "com.google.Chrome", "a cache folder names its app")
t.assertEqual(Verify.bundleId(home .. "/Library/Group Containers/ABC.com.example.shared/x"), "ABC.com.example.shared", "group containers name their owner")
t.assertEqual(Verify.bundleId(home .. "/Documents/site"), nil, "ordinary folders name no app")

local ok, why = check({path = home .. "/Library/Caches/com.google.Chrome"})
t.expect(not ok and why.code == "running", "a cache is skipped while its app is open")
ok, why = check({path = home .. "/Library/Caches/com.google.Chrome.helper"})
t.expect(not ok and why.code == "running", "a helper's cache is skipped while its parent app is open")
ok, why = check({path = home .. "/Documents/site/node_modules", resourceId = "derived"}, {appIcon = "com.apple.dt.Xcode"})
t.expect(not ok and why.reason == "Xcode was open", "a catalog location names the app that blocks it")
ok = check({path = home .. "/Documents/site/node_modules"}, {marker = home .. "/Documents/site/package.json"})
t.expect(ok, "a build folder whose project file is still there moves")
ok, why = check({path = home .. "/Documents/old/node_modules"}, {marker = home .. "/Documents/old/package.json"})
t.expect(not ok and why.code == "marker", "a build folder whose project file is gone is skipped")
ok, why = check({path = home .. "/Downloads/big.iso", identity = {inode = 9, device = 1}})
t.expect(not ok and why.code == "replaced", "an item replaced since it was marked is skipped")
t.expect(check({path = home .. "/Downloads/big.iso", identity = {inode = 7, device = 1}}), "the same item moves")
ok, why = check({path = home .. "/Downloads/gone.dmg"})
t.expect(not ok and why.code == "missing", "an item that is gone is skipped")
ok, why = check({path = home .. "/Library/Containers/com.old.App", leftover = true})
t.expect(not ok and why.code == "reinstalled", "a leftover whose app is installed again is skipped")
ok, why = check({path = "/System/Library/Caches/x"})
t.expect(not ok and why.code == "protected", "protected system locations never move, whatever marked them")
ok, why = check({path = "/usr/lib/libx.dylib"})
t.expect(not ok and why.code == "protected", "system libraries never move")
ok, why = check({path = home .. "/Documents"})
t.expect(not ok and why.code == "location", "standard folders never move")

-- The result reads like Headroom's sheet.
local text = Verify.summary({moved = 12, movedBytes = 18.2e9, skipped = {"Xcode was open", "Xcode was open", "it is no longer there"},
	freeBefore = 40e9, freeNow = 40.1e9})
t.expect(text:find("18.2 GB moved to the Trash · 12 items", 1, true), "the headline says what moved")
t.expect(text:find("2 skipped because Xcode was open", 1, true) and text:find("1 skipped because it is no longer there", 1, true), "skips are grouped by reason")
t.expect(text:find("Free before: 40.0 GB", 1, true) and text:find("After emptying the Trash, up to 58.3 GB", 1, true), "free space before, now and after emptying")
t.assertEqual(Verify.summary({moved = 1, movedBytes = 1e6}), "1.0 MB moved to the Trash · 1 item", "a single item reads naturally")

-- The Review sheet checks each item as it moves and reports what it skipped.
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local service = Mock.new()
local app = Controller.new(service)
app:createWindow()
local mhome = service.home
service.confirmAction = function() return true end
local iso, pkg = mhome .. "/Downloads/ubuntu-24.04-desktop-arm64.iso", mhome .. "/Downloads/Zoom Installer.pkg"
local cache = mhome .. "/Library/Caches/com.mock.oldeditor"
local site = mhome .. "/Documents/website/node_modules"
for _, path in ipairs({iso, pkg, cache}) do
	t.expect(app.env.basket:toggle({path = path, name = path:match("([^/]+)$"), bytes = 1}), "marks " .. path:match("([^/]+)$"))
end
t.expect(app.env.basket:toggle({path = site, name = "Node modules · website", resourceId = "mock-website-node-modules"}), "marks a discovered build folder")
t.expect(Marks:find(iso).identity ~= nil, "an item's identity is recorded when it is marked")
service.runningApps = {"com.mock.oldeditor"}
service.replace(pkg)
service.trash(mhome .. "/Documents/website/package.json")
app:openReview()
t.expect(app.env:page("basket"):trash(), "the cleanup runs")
t.expect(app.env:page("basket").done[iso] == "Moved to Trash", "an unchanged item moves")
t.assertEqual(Marks:find(iso), nil, "a moved item leaves the basket")
t.assertEqual(app.env:page("basket").results[pkg], "Skipped", "a replaced item is skipped")
t.assertEqual(app.env:page("basket").results[cache], "Skipped", "a cache whose app is open is skipped")
t.expect(Marks:find(pkg) and Marks:find(cache), "skipped items stay marked")
local summary = app.env:page("basket").refs.reviewSummary.text
t.assertEqual(app.env:page("basket").results[site], "Skipped", "a build folder whose project file is gone is skipped")
t.expect(summary:find("moved to the Trash · 1 item", 1, true), "the sheet says what moved")
t.expect(summary:find("skipped because the project file that identified it is gone", 1, true), "the sheet explains a lost proof")
t.expect(summary:find("skipped because a different item is at its place now", 1, true), "the sheet explains a replaced item")
t.expect(summary:find("skipped because com.mock.oldeditor was open", 1, true), "the sheet names the open app")
t.expect(summary:find("After emptying the Trash, up to", 1, true), "the sheet shows free space after emptying")
app:show("overview")

os.exit(t.summary() and 0 or 1)
