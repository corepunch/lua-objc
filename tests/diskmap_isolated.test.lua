_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Controller = require("apps.diskmap.Controller")
local Provider = require("apps.diskmap.services.Provider")
local Mock = require("apps.diskmap.services.Mock")
local Model = require("data.model")
local Suggestions = require("apps.diskmap.models.Suggestions")
local Manifest = require("data.manifest")

local function fails(args, message)
	local ok, err = pcall(Provider.launch, args)
	t.expect(not ok and tostring(err):find(message, 1, true), "invalid launch: " .. message)
end
fails({"--isolated"}, "requires --page")
fails({"--page=nope", "--isolated"}, "Valid pages:")
local launch = Provider.launch({"--showcase", "--page=cleanup", "--isolated"})
local mock = launch.service
local effects = {}
for _, name in ipairs({"monitor", "onOpenFiles", "watch", "notify", "removeNotification", "saveHistory"}) do
	mock[name] = function() table.insert(effects, name) end
end
mock.loadHistorySetting = function() return true end
mock.loadFlag = function() return true end
local isolated = Controller.new(mock, launch)
local window = isolated:createWindow()
t.assertEqual(isolated.destination, "cleanup", "isolated launch selects its page")
t.expect(isolated.navigation.refs == nil, "isolated launch has no sidebar")
t.expect(isolated.destination ~= "onboarding" and isolated.destination ~= "tour", "isolated launch skips onboarding and tour")
t.assertEqual(#effects, 0, "isolated launch registers no process hooks and writes no history")
local total = Suggestions:presentation(isolated.env:sources()).eligibleBytes
local full = Controller.new(Mock.new({showcase = true}), {})
full:createWindow()
t.assertEqual(Suggestions:presentation(full.env:sources()).eligibleBytes, total, "Clean Up totals are independent of launch mode")
t.assertEqual(#isolated.shortcuts, #full.shortcuts, "both modes offer the same keyboard shortcuts")
for index, shortcut in ipairs(full.shortcuts) do
	t.assertEqual(isolated.shortcuts[index].title, shortcut.title, "shortcut title " .. index)
	t.assertEqual(isolated.shortcuts[index].key, shortcut.key, "shortcut key " .. index)
end

-- Every manifest destination is a request which can render alone, including
-- workflows hidden by the full app's sidebar. Reuse one scanned environment.
for _, entry in ipairs(Manifest.load("apps/diskmap/app.xml").order) do
	isolated:show(entry.id)
	local page = isolated.env:page(entry.id)
	t.assertEqual(page, isolated.env:page(entry.id), entry.id .. " is memoized")
	t.expect(isolated.page.template ~= nil, entry.id .. " mounts")
	isolated.page:marksChanged()
	t.expect(isolated.window == window, entry.id .. " uses the same window")
end
isolated:show("overview")
isolated:show("cleanup")
t.expect(isolated.navigation:back(), "cross-page navigation retains Back")
t.assertEqual(isolated.destination, "overview", "Back swaps the page in place")
t.expect(isolated.navigation:forward(), "cross-page navigation retains Forward")
t.assertEqual(isolated.destination, "cleanup", "Forward swaps the page in place")
t.assertEqual(#effects, 0, "page visits add no process effects")
local ok = pcall(isolated.show, isolated, "nope")
t.expect(not ok, "unknown navigation cannot leave a blank capture")
local page = isolated.env:page("cleanup")
t.expect(page ~= full.env:page("cleanup"), "another window has its own request")
isolated:dispose(); full:dispose()
window:close(); full.window:close()
t.assertEqual(#effects, 0, "isolated disposal cannot unregister another window's process hook")
os.exit(t.summary() and 0 or 1)
