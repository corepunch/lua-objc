_G.__headless = true
local t = require("TestKit")
local Map = require("apps.diskmap.knowledge.Filesystem")
local Library = require("apps.diskmap.knowledge.Library")
local Explain = require("apps.diskmap.helpers.Explain")
local Leftovers = require("apps.diskmap.helpers.Leftovers")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Every known location says in a few words what it is: the line under its
-- name in a folder list, short enough to sit beside the item count.
local NOTE = {longest = 48}
for _, area in ipairs(Map.areas) do
	for _, location in ipairs(area.locations) do
		t.expect(type(location.note) == "string" and #location.note > 0, location.path .. " has a note")
		t.expect(#(location.note or "") <= NOTE.longest, location.path .. "'s note fits a row")
	end
end
for parent, rule in pairs(Library.parents) do
	t.expect(rule.note and rule.unknownNote, parent .. " has notes for owned and unclaimed children")
end
for name, entry in pairs(Library.names) do t.expect(entry.note ~= nil, name .. " has a note") end
for name, entry in pairs(Library.volumeGroup.children) do t.expect(entry.note ~= nil, "Preboot's " .. name .. " has a note") end

-- Preboot: neither of its big folders is a mystery or junk.
local group = "/System/Volumes/Preboot/144C563D-5398-4ACA-BFB2-E4F6D5F0EF38"
local install = Explain.path(group, {})
t.assertEqual(install and install.owner, "macOS", "a volume group folder in Preboot is macOS's")
t.expect(install.note:find("not junk", 1, true) ~= nil, "and its note says it is not junk")
t.expect(Explain.path(group .. "/cryptex1", {}).what:find("clones", 1, true) ~= nil, "cryptex1 explains why it counts twice")
t.assertEqual(Explain.path(group .. "/cryptex1/current", {}), nil, "a folder deeper inside is not guessed at")
t.expect(Explain.path("/System/Volumes/Preboot/Cryptexes", {}).note:find("Safari", 1, true) ~= nil, "Cryptexes names Safari")
t.expect(Explain.path("/System/Volumes/Preboot/Cryptexes/Rosetta", {}).what ~= nil, "Rosetta's cryptex is explained")

-- Notes name the owner a Library rule resolves.
local apps = Leftovers.index({{bundleId = "com.apple.mail", name = "Mail"}})
local mail = Explain.path("/Users/me/Library/Caches/com.apple.mail", {home = "/Users/me", apps = apps})
t.assertEqual(mail.note, "Mail's cache · rebuilt when needed", "a cache's note names its app")
local gone = Explain.path("/Users/me/Library/Caches/com.removed.App", {home = "/Users/me", apps = apps})
t.assertEqual(gone.note, "Cache no installed app claims", "an unclaimed cache says so")
t.assertEqual(Explain.path("/Users/me/Library/Caches/Mystery", {home = "/Users/me", apps = apps}).note, "Cache", "a plain name is only its kind")
t.expect(Explain.path("/x/.git", {}).note:find("Git", 1, true) ~= nil, "a dot-folder known by name has a note")

-- The Folder Map: notes under row names, the explanation as their tooltip,
-- and what the open folder is above its contents.
local home = "/tmp/diskmap-notes-test"
local snapshot = home .. "/fixture.bin"
os.execute("rm -rf " .. home .. " && mkdir -p " .. home)
local GB = 1e9
local items = {
	{group .. "/cryptex1/current/os.dmg", 24 * GB},
	{group .. "/boot/kernel", GB / 10},
	{"/System/Volumes/Preboot/Cryptexes/Rosetta/System/rosetta.dmg", 7 * GB},
	{"/System/Volumes/Preboot/Cryptexes/OS/System/os.dmg", 3 * GB},
	{"~/Downloads/Installer.dmg", 3 * GB},
	{"~/Downloads/Archive/Old/a.zip", 2 * GB},
	{"~/Downloads/Archive/Old/b.zip", GB},
	{"~/Downloads/Photos/c.jpg", GB},
}
table.sort(items, function(a, b) return a[1] < b[1] end)
local records = {}
for _, item in ipairs(items) do table.insert(records, {path = item[1], allocatedBytes = item[2]}) end
require("apps.diskmap.services.Scanner").writeSnapshot(snapshot, {capacityBytes = 500 * GB, availableBytes = 200 * GB, visited = #items}, records)
local service = Mock.new({home = home, fixturePath = snapshot})
local app = Controller.new(service)
app:createWindow()
app:show("folder", {path = "/System/Volumes/Preboot"})
local page = app.env:page("folder")
local data = page:data()
local rows = {}
for _, row in ipairs(data.lists.folderList) do rows[row.name] = row end
local install, cryptexes = rows["144C563D-5398-4ACA-BFB2-E4F6D5F0EF38"], rows.Cryptexes
t.expect(install and install.subtitle:find("Boot files of this macOS install", 1, true) == 1, "the volume group row opens with its note")
t.expect(cryptexes and cryptexes.subtitle:find("Safari", 1, true) ~= nil, "the Cryptexes row says what it carries")
t.expect(install and install.help:find("FileVault", 1, true) ~= nil, "a row's tooltip is the whole explanation")
local about = data.context and data.context[1]
t.expect(about and about.data.heading == "About Preboot", "the open folder is explained above its contents")
t.expect(about and about.data.text:find("clones", 1, true) ~= nil, "with what the knowledge of macOS says about it")
t.expect(app.page.refs.folderAbout ~= nil, "the explanation renders")
local cell = require("AppKitNative")._tableCell(app.page.refs.folderList, 0, 0)
t.expect(cell.secondaryTextField.stringValue:find("not junk", 1, true) ~= nil, "the note renders under the name")

-- The rings show the same three levels as the rectangles, splitting the
-- donut's width instead of widening it.
app:show("folder", {path = service.home .. "/Downloads"})
data = page:data()
local deepest = 1
for _, mark in ipairs(data.breakdown.marks) do deepest = math.max(deepest, mark.ring or 1) end
t.expect(deepest > 1, "the folder ring is a sunburst")
t.assertEqual(data.breakdown.marks, data.breakdown.rectangles, "rings and rectangles draw the same nodes")
t.expect(app.page.refs.breakdownChart ~= nil, "the sunburst renders")

-- No gaps: the drawn children of a folder fill its whole angle, scaled up
-- when slivers were left out, so outer rings end where their parent does.
local Sectors = require("ui.sectors")
local function gapless(marks, what)
	local byId, last = {}, {}
	for _, sector in ipairs(Sectors.layout(marks, 260, 0.618, 1)) do
		byId[sector.id] = sector
		if sector.parent and (not last[sector.parent] or sector.spanEnd > last[sector.parent]) then last[sector.parent] = sector.spanEnd end
	end
	local checked = 0
	for id, ending in pairs(last) do
		checked = checked + 1
		t.expect(math.abs(ending - byId[id].spanEnd) < 1e-6, what .. ": the inside of " .. id .. " fills its arc")
	end
	t.expect(checked > 0, what .. " has outer rings")
end
gapless(data.breakdown.marks, "Folder Map")
gapless(require("apps.diskmap.models.Categories"):mapNodes(""), "Storage Map")

-- The Overview: categories with their contents outside, and free space
-- running through every ring so the track stays closed.
app:show("overview")
local chart = require("apps.diskmap.models.Categories"):chart(service.diskSpace())
local rings, free = 1, 0
for _, mark in ipairs(chart.sunburst) do
	rings = math.max(rings, mark.ring or 1)
	if mark.id == "free" or (mark.parent or ""):find("^free") then free = free + 1 end
end
t.expect(rings > 1, "the Overview ring shows what is inside each category")
t.assertEqual(free, rings, "free space continues through every ring")
for _, mark in ipairs(chart.rectangles) do t.expect(not mark.id:find("#ring", 1, true), "rectangles carry no ring continuations") end

-- A location in the Overview's outer rings opens its folder, not the Map;
-- a category still opens the Map inside it.
local overviewPage = app.env:page("overview")
overviewPage:chartSelect("preboot")
t.assertEqual(app.destination, "folder", "clicking Preboot on the Overview ring opens the Folder Map")
t.assertEqual(app.env:page("folder").path, "/System/Volumes/Preboot", "at Preboot")
app:show("overview")
app.env:page("overview"):chartSelect("macos")
t.assertEqual(app.destination, "map", "clicking a category opens the Storage Map")
t.assertEqual(app.env:page("map").focusId, "macos", "inside it")

os.exit(t.summary() and 0 or 1)
