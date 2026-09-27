_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

-- The development runtime has no bundle, so it has no notification center;
-- the API says so instead of crashing, and Diskmap hides what needs it.
t.assertEqual(ns.notifications.available(), false, "an unbundled process cannot post notifications")
t.assertEqual(ns.notifications.post({id = "test", title = "Hello"}), false, "posting reports that nothing was posted")
local answer
ns.notifications.requestAuthorization(function(granted, message) answer = {granted, message} end)
for _ = 1, 20 do if answer then break end; ns._runLoopTick(0.02) end
t.expect(answer and answer[1] == false and answer[2]:find("bundle", 1, true), "authorization explains why it is unavailable")
t.expect(not pcall(ns.notifications.post, {title = "No id"}), "a notification requires an id")

-- Responses reach the callback registered for the notification.
local responded
ns._notificationRegister("reminder", function(id, action) responded = {id, action} end)
ns._notificationRespond("reminder", "action")
t.expect(responded and responded[1] == "reminder" and responded[2] == "action", "a clicked action runs the notification's callback")
ns.notifications.remove("reminder")
responded = nil
ns._notificationRespond("reminder")
t.assertEqual(responded, nil, "a removed notification no longer responds")

local uikit = assert(io.open("lua/embedded/UIKit.lua")):read("*a")
t.expect(uikit:find('require("ui.notifications").install(UIKit, bridge)', 1, true) ~= nil, "UIKit installs the same notification API")
os.exit(t.summary() and 0 or 1)
