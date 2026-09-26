_G.__headless = true
local t = require("TestKit")
local native = require("StorageScan")
local System = require("apps.diskmap.services.System")
local Scanner = require("apps.diskmap.services.Scanner")
t.assertEqual(native.backend, "getattrlistbulk", "plugin uses native bulk metadata enumeration")
local empty = native.scan({})
t.assertEqual(empty.completed, 0, "empty scan has no invented roots")
t.assertEqual(empty.failure, "", "empty scan completes successfully")
for _, paths in ipairs({{"relative"}, {"/tmp/../etc"}, {"/tmp/./file"}, {"/tmp/zero\0suffix"}, {"/tmp/\255"}}) do
	t.assertThrows(function() native.scan(paths) end, "invalid root is rejected before scanning")
end
t.assertThrows(function() native.scan({}, {"relative"}) end, "invalid exclusion is rejected")
t.assertThrows(function() native.poll({}) end, "only native job handles are accepted")
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/storage-scan.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local function mkdir(path) assert(os.execute("/bin/mkdir " .. System.quote(path))) end
local function write(path, text)
	local file = assert(io.open(path, "wb")); file:write(text); file:close()
end
local files = root .. "/files"
mkdir(files)
-- More entries than fit in one native buffer; empty files still have identities.
for i = 1, 1200 do write(files .. "/" .. i, "") end
local many = native.scan({files})
t.assertEqual(many.visited, 1201, "bulk enumeration consumes every buffer exactly once")
t.expect(many.bulkCalls > 2, "large directory crosses native buffer boundaries")
t.assertEqual(many.errors, 0, "bulk buffer parsing has no metadata errors")
local file = root .. "/allocated"
write(file, string.rep("a", 8192))
local first = native.scan({file})
write(file, string.rep("b", 16384))
local second = native.scan({file})
t.assertEqual(first.trees[1].kb, 8, "first scan measures original allocation")
t.assertEqual(second.trees[1].kb, 16, "new scan measures changed allocation without a cache")
local snapshotPath = root .. "/mock-snapshot.bin"
local export = native.exportStart({file}, {}, snapshotPath, {capacityBytes = 1000000, availableBytes = 250000})
local exported, exportResult = false, nil
local exportDeadline = os.clock() + 0.5
repeat
	exported, exportResult = native.poll(export)
until exported or os.clock() >= exportDeadline
t.expect(exported, "metadata snapshot export completes asynchronously")
t.assertEqual(exportResult.exportedFiles, 1, "snapshot includes each scanned regular file once")
local snapshotFile = assert(io.open(snapshotPath, "rb"))
local snapshotBody = snapshotFile:read("*a"); snapshotFile:close()
local magic = snapshotBody:sub(1, 8)
t.assertEqual(magic, "DMOCK001", "snapshot uses the versioned binary Mock HDD format")
t.expect(not snapshotBody:find(string.rep("b", 32), 1, true), "snapshot does not contain file contents")
local importedMock = require("apps.diskmap.services.Mock").new({fixturePath = snapshotPath})
t.assertEqual(importedMock.fixture.capacityBytes, 1000000, "snapshot preserves internal disk capacity metadata")
t.assertEqual(importedMock.items[1].path, file, "snapshot stores the absolute file path")
t.assertEqual(importedMock.items[1].allocatedBytes, 16384, "snapshot stores allocated bytes without opening file contents")
t.assertEqual(importedMock.items[1].countedBytes, 16384, "snapshot records one hard-link accounting charge")
t.assertEqual(importedMock.scan({root}, {}).trees[1].kb, 16, "exported snapshot loads through the Mock provider")
os.remove(snapshotPath)
local sparse = root .. "/sparse"
local f = assert(io.open(sparse, "wb")); f:seek("set", 32 * 1024 * 1024); f:write("x"); f:close()
local allocation = native.scan({sparse})
t.expect(allocation.trees[1].kb > 0 and allocation.trees[1].kb < 32768, "sparse files use allocated bytes, not logical length")
local duplicate = native.scan({file, file})
t.assertEqual(duplicate.trees[1].kb + duplicate.trees[2].kb, 16, "duplicate roots share one identity ledger")
local blocked = root .. "/blocked"
mkdir(blocked)
assert(os.execute("/bin/chmod 000 " .. System.quote(blocked)))
local denied = native.scan({blocked, root .. "/missing"})
assert(os.execute("/bin/chmod 700 " .. System.quote(blocked)))
t.assertEqual(denied.rootStates[1], "unreadable", "denied directory is not a completed zero")
t.expect(denied.trees[1].partial, "partial root retains uncertainty")
t.assertEqual(denied.rootStates[2], "missing", "missing root is distinguished from denial")
t.assertEqual(denied.errors, 1, "one denied root produces one issue")
local job = native.start({files})
t.assertEqual(type(job), "userdata", "background scan owns a native handle")
native.cancel(job); native.cancel(job)
local done, progress = native.poll(job)
t.expect(type(done) == "boolean" and (progress == nil or type(progress) == "table"), "polling cancellation is nonblocking")
local finalize = getmetatable(job).__gc
finalize(job); finalize(job)
t.assertThrows(function() native.poll(job) end, "finalized handle cannot be reused")
local wrapped = Scanner.start({files})
Scanner.cancel(wrapped); Scanner.cancel(wrapped)
t.expect(wrapped.cancelled and wrapped.handle == nil, "service cancellation releases native handle")
local cancelled, result = Scanner.poll(wrapped)
t.expect(cancelled and result.failure == "Measurement cancelled.", "released job reports cancellation")
t.assertEqual(native.scan({file}).trees[1].kb, 16, "cancelling one scan does not affect another")
-- The service emits each completed-location count once, but never drops completion.
local finished, snapshot = false, {completed = 1, total = 2}
local fakeNative = {poll = function() return finished, snapshot end}
local environment = setmetatable({
	package = {searchpath = function() return "/fixture/StorageScan.dylib" end, cpath = ""},
	require = function(name)
		assert(name == "App")
		return {loadNativePlugin = function() return fakeNative end}
	end,
}, {__index = _G})
local service = assert(loadfile("apps/diskmap/services/Scanner.lua", "t", environment))()
local pending = {handle = {}}
local isDone, update = service.poll(pending)
t.expect(not isDone and update == snapshot, "first completed location publishes progress")
isDone, update = service.poll(pending)
t.expect(not isDone and update == nil, "unchanged progress does not rebuild the UI")
snapshot = {completed = 2, total = 2}
isDone, update = service.poll(pending)
t.expect(not isDone and update == snapshot, "next location publishes new progress")
finished = true
isDone, update = service.poll(pending)
t.expect(isDone and update == snapshot and pending.handle == nil, "final result is delivered even with unchanged location count")
-- Optional summaries: ranked large files, old files, extension totals and one
-- level of per-root breakdown, published only with the final result.
local summary = root .. "/summary"
mkdir(summary); mkdir(summary .. "/Movies"); mkdir(summary .. "/Movies/Nested")
write(summary .. "/Movies/clip.MOV", string.rep("m", 64 * 1024))
write(summary .. "/Movies/Nested/older.mov", string.rep("o", 32 * 1024))
write(summary .. "/archive.zip", string.rep("z", 16 * 1024))
write(summary .. "/tiny.txt", "t")
write(summary .. "/.hidden", string.rep("h", 8192))
assert(os.execute("/usr/bin/touch -t 202001010000 " .. System.quote(summary .. "/Movies/Nested/older.mov")))
local plain = native.scan({summary})
t.expect(plain.largeFiles == nil and plain.extensions == nil and plain.breakdowns == nil, "summaries are off unless requested")
local cutoff = os.time() - 365 * 24 * 3600
local summarized = native.scan({summary}, {}, {files = 2, minimumFileBytes = 12 * 1024, oldBefore = cutoff, extensions = true, breakdown = true})
t.assertEqual(#summarized.largeFiles, 2, "large files are capped at the requested count")
t.assertEqual(summarized.largeFiles[1].path, summary .. "/Movies/clip.MOV", "large files are ranked largest first")
t.assertEqual(summarized.largeFiles[2].path, summary .. "/Movies/Nested/older.mov", "the ranking keeps the next largest file")
t.assertEqual(summarized.largeFiles[1].bytes, 64 * 1024, "large files carry allocated bytes")
t.expect(summarized.largeFiles[1].used >= cutoff, "recent files carry their last use time")
t.assertEqual(#summarized.oldFiles, 1, "only files unused since the cutoff are old")
t.assertEqual(summarized.oldFiles[1].path, summary .. "/Movies/Nested/older.mov", "old files keep their path")
t.assertEqual(summarized.oldBytes, 32 * 1024, "old bytes total every old file")
local byExtension = {}
for _, row in ipairs(summarized.extensions) do byExtension[row.extension] = row end
t.assertEqual(byExtension.mov.bytes, 96 * 1024, "extensions are case-insensitive and summed")
t.assertEqual(byExtension.mov.count, 2, "extension rows count files")
t.assertEqual(byExtension.mov.oldBytes, 32 * 1024, "extension rows keep their old share")
t.assertEqual(byExtension.zip.bytes, 16 * 1024, "each extension has its own row")
t.expect(byExtension[""] and byExtension[""].count == 1, "dot files have no extension")
local children = {}
for _, child in ipairs(summarized.breakdowns[1]) do children[child.name] = child end
t.assertEqual(#summarized.breakdowns[1], 4, "the breakdown lists each immediate child once")
t.expect(children.Movies.directory == true and children["archive.zip"].directory == false, "breakdown marks directories")
t.expect(children.Movies.kb >= 96 and children.Nested == nil, "breakdown sums descendants without listing them")
t.assertEqual(children["archive.zip"].kb, 16, "top-level files appear in the breakdown")
for _, path in ipairs({"/Movies/Nested/older.mov", "/Movies/clip.MOV", "/archive.zip", "/tiny.txt", "/.hidden", "/Movies/Nested", "/Movies", ""}) do os.remove(summary .. path) end
for i = 1, 1200 do os.remove(files .. "/" .. i) end
for _, path in ipairs({files, file, sparse, blocked, root}) do os.remove(path) end
os.exit(t.summary() and 0 or 1)
