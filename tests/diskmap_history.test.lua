_G.__headless = true
local t = require("TestKit")
local Harness = require("tests.support.diskmap")
local Provider = require("apps.diskmap.services.Provider")
local OperationLog = require("apps.diskmap.helpers.OperationLog")
local Location = require("data.location")

-- Browser-like history: every page and every folder looked inside is a
-- visit Back and Forward return to, as locations.
local app, service = Harness.app()
t.assertEqual(app:location(), "/overview", "the app opens on the Overview")
app:show("xcode")
app:show("folder", {path = service.home .. "/Developer"})
app:show("folder", {path = service.home .. "/Developer", focus = service.home .. "/Developer/rustle"})
t.expect(app:location():find("/folder/" .. service.home .. "/Developer?focus=", 1, true) == 1 and app:location():find("rustle", 1, true), "looking inside is a visit")
t.expect(app.navigation:back(), "Back")
t.assertEqual(app:location(), "/folder/" .. service.home .. "/Developer", "returns to the folder")
t.expect(app.navigation:back(), "Back again")
t.assertEqual(app.destination, "xcode", "returns to the page before")
t.expect(app.navigation:forward(), "Forward")
t.assertEqual(app.destination, "folder", "returns forward")
app:show("system")
t.expect(not app.navigation:canGoForward(), "a new visit drops the forward history")
t.expect(app.navigation:canGoBack(), "and can go back")
app:go("/history")
t.assertEqual(app.destination, "history", "a location opens its page")
t.expect(app.window.title == "Action History", "the window is titled by the page")
app:dispose()

-- Launch flags.
t.assertEqual(Provider.launch({"--showcase", "--page=xcode"}).page, "/xcode", "a page id is its location")
t.assertEqual(Provider.launch({"--showcase", "--page=/folder//Users/me"}).page, "/folder//Users/me", "--page takes a location")
t.assertThrows(function() Provider.launch({"--showcase", "--page=/nowhere"}) end, "an unknown page is refused")
t.assertThrows(function() Provider.launch({"--showcase", "--isolated"}) end, "--isolated needs a page")
t.expect(Provider.launch({"--showcase"}).service.mock, "--showcase is the synthetic Mac")
t.assertEqual(Provider.launch({"--showcase", "--folder=/tmp"}).folder, "/tmp", "--folder opens a folder")

-- The action log: one line per action, read back newest first.
local line = OperationLog.format({action = "Move to Trash", ok = true, bytes = 1.5e9, target = "/Users/me/x\ty", detail = "a\nb"}, 0)
t.assertEqual(line, "1970-01-01T00:00:00Z\tMove to Trash\tok\t1500000000\t/Users/me/x y\ta b", "fields are tab separated and cleaned")
local rows = OperationLog.rows({line, OperationLog.format({action = "Delete", ok = false, bytes = 0, target = "/x", detail = "no"}, 60)})
t.assertEqual(rows[1].name, "Delete", "newest first")
t.assertEqual(rows[1].result, "Failed: no", "a failure carries its detail")
t.assertEqual(rows[2].size, "1.5 GB", "sizes are formatted")
t.expect(Location.parse("/folder//Users/me?focus=/Users/me/x", require("data.manifest").load("apps/diskmap/app.xml").pages), "folder locations parse")

os.exit(t.summary() and 0 or 1)
