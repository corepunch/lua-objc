_G.__headless = true
local t = require("TestKit")
local Store = require("apps.diskmap.Store")
local Scans = require("apps.diskmap.models.Scans")
local Locations = require("apps.diskmap.models.Locations")

-- The disk is measured once; a removal or move changes the model, and every
-- page reads the change from it without measuring again.
local model = Store.new("/Users/test")
local downloads, trash, derived = Locations:find("downloads").path, Locations:find("user-trash").path, Locations:find("derived").path
local dmg, zip = downloads .. "/Installer.dmg", downloads .. "/Archive/backup.zip"
local function reset()
	model.measurements.downloads = {bytes = 10e9, logicalBytes = 10e9, status = "complete"}
	model.measurements["user-trash"] = {bytes = 1e9, status = "complete"}
	model.measurements.derived = {bytes = 6e9, status = "complete"}
	model.breakdowns = {downloads = {{name = "Installer.dmg", kb = 4e9 / 1024}, {name = "Archive", kb = 3e9 / 1024, directory = true}}}
	model.files = {large = {{path = dmg, bytes = 4e9}, {path = zip, bytes = 2e9}}, old = {{path = zip, bytes = 2e9}},
		extensions = {{extension = "dmg", bytes = 4e9, count = 1}, {extension = "zip", bytes = 2e9, count = 1}}, oldBytes = 2e9, oldCount = 1}
end

-- A file moved to the Trash: its location shrinks, the Trash grows by as much.
reset()
local before = Scans:measured()
Scans:remove(dmg, 4e9, trash)
t.assertEqual(model.measurements.downloads.bytes, 6e9, "the location holding the file loses its size")
t.assertEqual(model.measurements.downloads.logicalBytes, 6e9, "and so does its logical size")
t.assertEqual(model.measurements["user-trash"].bytes, 5e9, "the Trash holds it until it is emptied")
t.assertEqual(Scans:measured(), before, "moving to the Trash frees nothing")
t.assertEqual(#model.breakdowns.downloads, 1, "the file leaves its location's immediate children")
t.assertEqual(model.breakdowns.downloads[1].name, "Archive", "the other children stay")
t.assertEqual(#model.files.large, 1, "the file leaves Large Files")
t.assertEqual(model.files.extensions[1].bytes, 0, "and its type's total")
t.assertEqual(model.files.extensions[2].bytes, 2e9, "other types are untouched")

-- A file deep in a folder: the child holding it shrinks, the old-file totals too.
Scans:remove(zip, 2e9)
t.assertEqual(model.measurements.downloads.bytes, 4e9, "a permanent removal shrinks the location")
t.assertEqual(model.breakdowns.downloads[1].kb, 1e9 / 1024, "the child folder that held it shrinks")
t.assertEqual(#model.files.large + #model.files.old, 0, "it leaves both file rankings")
t.assertEqual(model.files.oldBytes, 0, "the old-file total follows")
t.assertEqual(model.files.oldCount, 0, "and its count")

-- A whole location moved to the Trash measures zero, whatever size the caller gave.
Scans:remove(derived, nil, trash)
t.assertEqual(model.measurements.derived.bytes, 0, "a trashed location measures zero")
t.assertEqual(model.measurements.derived.status, "complete", "as a complete measurement, not an unknown one")

-- Emptying the Trash.
reset()
before = Scans:measured()
Scans:remove(trash)
t.assertEqual(model.measurements["user-trash"].bytes, 0, "an emptied Trash measures zero")
t.assertEqual(Scans:measured(), before - 1e9, "and the measured total falls by its size")

-- Edge cases: nothing to remove, a path no location holds.
reset()
Scans:remove(nil, 5e9); Scans:remove("", 5e9)
t.assertEqual(model.measurements.downloads.bytes, 10e9, "no path changes nothing")
Scans:remove("/Volumes/Other/file", 5e9)
t.assertEqual(Scans:measured(), 17e9, "a path outside every location changes no total")
Scans:remove(downloads .. "/huge.iso", 50e9)
t.assertEqual(model.measurements.downloads.bytes, 0, "a location never measures below zero")
model.files = nil
Scans:remove(dmg, 1)
t.expect(true, "a model without file rankings takes a removal")

-- A location its owner cleaned takes the size measured of it afterward.
reset()
model.files.large = {{path = derived .. "/Build/app.o", bytes = 1e9}}
Scans:resize("derived", 2e9)
t.assertEqual(model.measurements.derived.bytes, 2e9, "the cleaned location takes its new size")
t.assertEqual(#model.files.large, 0, "files inside it leave Large Files")
t.assertEqual(model.measurements.downloads.bytes, 10e9, "other locations are untouched")

os.exit(t.summary() and 0 or 1)
