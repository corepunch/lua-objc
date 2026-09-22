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
for i = 1, 1200 do os.remove(files .. "/" .. i) end
for _, path in ipairs({files, file, sparse, blocked, root}) do os.remove(path) end
os.exit(t.summary() and 0 or 1)
