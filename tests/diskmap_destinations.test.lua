_G.__headless = true
local t = require("TestKit")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local Locations = require("apps.diskmap.models.Locations")
local app = Controller.new(Mock.new())
app:createWindow()
for _, row in ipairs(Locations:all()) do
	local destination = row:destination()
	t.expect(app.env.manifest.pages[destination.page] ~= nil, row.id .. " opens an existing page")
	t.expect(destination.sheet == nil and destination.category == nil, row.id .. " has no modal destination")
end
for _, id in ipairs({"projects", "simulators", "derived", "devices", "archives", "xcode-app", "clt", "npm", "developer", "system-data", "containers"}) do
	local row = Locations:find(id)
	if row then
		local destination = row:destination()
		app:show("largest")
		app:open(id)
		t.assertEqual(app.destination, destination.page, id .. " opens its destination")
		if destination.params and destination.params.path then t.assertEqual(app.env:page("folder").path, row.path, "opens the selected location itself") end
		if destination.params and destination.params.focus then t.assertEqual(app.env:page("map").focusId, id, "groups drill into Storage Map") end
		t.expect(app.window.attachedSheet == nil, "opening a resource never attaches a sheet")
		app.navigation:back()
		t.assertEqual(app.destination, "largest", "Back returns to the originating list")
		app.navigation:forward()
		t.assertEqual(app.destination, destination.page, "Forward restores the destination")
	end
end
t.assertEqual(Locations:destination("xcode-app").page, "sdks", "an Xcode installation opens the SDK page")
t.assertEqual(Locations:destination("npm").page, "folder", "a cache opens its contents")
t.assertEqual(Locations:destination("developer").params.focus, "developer", "a category opens its map")
app:open("updates")
t.assertEqual(app.destination, "updates", "a page with no catalog row also navigates")
app:dispose()
os.exit(t.summary() and 0 or 1)
