_G.__headless = true
local t = require("TestKit")
local bridge = require("AppKitNative")
local VolumeContents = require("apps.diskmap.models.VolumeContents")

-- Hidden system folders at a volume's root are named and explained.
local rows, total = VolumeContents.rows("/Volumes/Stick", {
	{name = ".Trashes", kb = 2048, directory = true},
	{name = "Videos", kb = 4096, directory = true},
	{name = ".Spotlight-V100", kb = 1024, directory = true},
})
t.assertEqual(total, 7 * 1024 * 1024, "the top level is totalled")
t.assertEqual(rows[1].name, "Videos", "the largest item comes first")
local byPath = {}
for _, row in ipairs(rows) do byPath[row.path] = row end
t.expect(byPath["/Volumes/Stick/.Trashes"].name == "Trash on this disk" and byPath["/Volumes/Stick/.Trashes"].action == "emptyTrash",
	"the volume's Trash is recognised and emptied through Finder")
t.expect(byPath["/Volumes/Stick/.Spotlight-V100"].action == "spotlight", "the Spotlight index points to Spotlight settings")
t.expect(not byPath["/Volumes/Stick/Videos"].system, "ordinary folders are not system folders")

-- The Disks page measures an external disk on request.
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local service = Mock.new()
local app = Controller.new(service)
app:createWindow()
app:show("disks")
local page = app.pages.disks
t.expect(page.refs.contentsSection.hidden, "no disk is analysed until asked")
local menu = bridge._tableRowMenu(page.refs.external, 1)
t.assertEqual(menu[1].title, "Analyze Contents", "an external disk offers to analyse its contents")
bridge._tableRowMenu(page.refs.external, 1, 1)
t.expect(not page.refs.contentsSection.hidden and page.refs.contentsTitle.text == "Contents of Backup Drive", "its contents appear")
t.assertEqual(page.refs.contents.rowCount, 6, "every top-level item is listed")
local titles = {}
for index = 1, page.refs.contents.rowCount do
	local items = bridge._tableRowMenu(page.refs.contents, index)
	titles[items[1].title] = true
end
t.expect(titles["Empty Trash…"] and titles["Spotlight Settings…"], "the disk's Trash and index offer their owners' actions")
t.expect(titles["Mark for Cleanup"], "ordinary folders can be marked for cleanup")

-- The system volume is called sealed only when the measured state says so.
local Volumes = require("apps.diskmap.models.Volumes")
local function systemRow(sealed)
	local list = {Containers = {{ContainerReference = "disk3", CapacityCeiling = 100, Volumes = {
		{Name = "Macintosh HD", DeviceIdentifier = "disk3s1", Roles = {"System"}, CapacityInUse = 10, Sealed = sealed}}}}}
	return Volumes.apfs(list, "disk3").rows[1]
end
t.expect(systemRow("Yes").subtitle:find("sealed, read-only", 1, true), "a sealed volume is described as sealed")
t.expect(systemRow("No").subtitle:find("not sealed", 1, true), "an unsealed volume is not called sealed")
t.expect(not systemRow(nil).subtitle:find("sealed", 1, true), "an unknown seal state claims nothing")
os.exit(t.summary() and 0 or 1)
