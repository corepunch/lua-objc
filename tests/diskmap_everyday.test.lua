_G.__headless = true
local t = require("TestKit")
local Store = require("apps.diskmap.Store")
local Locations = require("apps.diskmap.models.Locations")
local Workflows = require("apps.diskmap.models.Workflows")
local Navigation = require("apps.diskmap.controllers.NavigationController")

-- Diskmap helps everyone, not only developers: the everyday apps whose media
-- piles up in ~/Library (chat media, cloud downloads, offline music and
-- video, Office, the browser's AI model) are catalog locations with their
-- own page, and each says where its app lets you reduce it.
local model = Store.new("/Users/test")
for _, id in ipairs({"whatsapp", "telegram", "telegram-desktop", "signal", "wechat", "zoom-recordings", "cloud-storage",
	"google-drive-cache", "spotify-downloads", "prime-video", "kindle", "voice-memos", "office-shared", "outlook",
	"chrome-profiles", "chrome-ai-model", "prism-launcher", "roblox", "openemu", "photos-library"}) do
	local row = Locations:find(id)
	t.expect(row ~= nil and row:isLeaf(), id .. " is a catalog location")
	t.expect(row and row.path:sub(1, #"/Users/test/") == "/Users/test/", id .. " lives in the home folder")
	t.expect(row and type(row.advice) == "string" and row.advice ~= "", id .. " says what to do with it")
	t.assertEqual(row and row.policy, "Review", id .. " is reviewed, never cleared as a cache")
end
t.assertEqual(Locations:find("whatsapp").path, "/Users/test/Library/Group Containers/group.net.whatsapp.WhatsApp.shared", "paths resolve against home")

-- Nested locations are measured apart from the folder that holds them.
t.assertEqual(Locations:find("outlook").path:match("^(.*)/Outlook$"), Locations:find("office-shared").path, "Outlook sits inside Office's shared data")
t.assertEqual(Locations:find("chrome-ai-model").path:match("^(.*)/OptGuideOnDeviceModel$"), Locations:find("chrome-profiles").path, "Chrome's model sits inside its profiles")

-- The Photos library stays behind the media opt-in, like the rest of Pictures.
t.expect(Locations:find("photos-library").mediaAccess, "the Photos library needs the media opt-in")
t.assertEqual(model.measurements["photos-library"].status, "excluded", "and is excluded until it is given")
-- A catalog `measurement` seeds the status; other locations start unmeasured
-- (Location:measurement, the method, must not be mistaken for the field).
t.assertEqual(model.measurements.snapshots.status, "unsupported", "a catalog measurement seeds its status")
t.assertEqual(model.measurements.whatsapp, nil, "other locations start unmeasured")

-- The page appears for a chat or cloud app, never on its own.
local everyday = Workflows:find("everyday")
t.expect(everyday ~= nil, "Everyday Apps is a kind of work")
t.expect(not everyday:present(function() return false end), "a Mac without these apps has no Everyday page")
t.expect(everyday:present(function(path) return path == "/Applications/WhatsApp.app" end), "WhatsApp shows it")
t.expect(not everyday:present(function(path) return path == "/Applications/Xcode.app" end), "Xcode does not")
t.assertEqual(Navigation.page("everyday").workflow, "everyday", "its sidebar row is gated on its own work")

-- It lists measured locations, largest first, across its sections.
model.measurements.telegram = {status = "complete", bytes = 30e9}
model.measurements.whatsapp = {status = "complete", bytes = 12e9}
model.measurements["cloud-storage"] = {status = "complete", bytes = 8e9}
model.measurements["chrome-ai-model"] = {status = "complete", bytes = 4e9}
model.measurements["spotify-downloads"] = {status = "complete", bytes = 0}
local page = everyday:presentation()
t.assertEqual(page.sections[1].rows[1].id, "telegram", "the largest chat comes first")
t.assertEqual(page.sections[1].rows[2].id, "whatsapp", "then the next")
for _, section in ipairs(page.sections) do
	for _, row in ipairs(section.rows) do t.expect(row.id ~= "spotify-downloads", "an empty location is not listed") end
end
t.expect(everyday:present(nil), "measured app data shows the page")

os.exit(t.summary() and 0 or 1)
