_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

-- ns.watch reports file system changes under a directory tree.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/watch.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local function waitFor(predicate)
	for _ = 1, 60 do
		if predicate() then return true end
		ns._runLoopTick(0.05)
	end
	return predicate()
end
local batches = {}
local scope = ns.Scope.new()
local handle = ns.Scope.withScope(scope, ns.watch, root, function(events) table.insert(batches, events) end, {latency = 0.02})
local start = ns.latestEventId()
local file = assert(io.open(root .. "/note.txt", "w")); file:write("x"); file:close()
os.execute("/bin/mkdir " .. root .. "/folder")
local function seen(name, flag)
	for _, events in ipairs(batches) do
		for _, event in ipairs(events) do
			if event.path:sub(-#name) == name and event[flag] then return event end
		end
	end
end
t.expect(waitFor(function() return seen("note.txt", "created") and seen("folder", "created") end), "created files and folders are reported")
t.expect(seen("folder", "created").directory, "directory events say so")
t.expect(seen("note.txt", "created").id > start, "events carry increasing event IDs")
scope:dispose()
t.expect(handle:isDisposed(), "the watch ends with the scope that created it")
local count = #batches
os.remove(root .. "/note.txt")
waitFor(function() return false end)
t.assertEqual(#batches, count, "a cancelled watch reports nothing more")

-- `since` replays what changed while nothing was watching.
local replayed = {}
local replay = ns.watch(root, function(events) for _, event in ipairs(events) do table.insert(replayed, event) end end, {since = start, latency = 0.02})
t.expect(waitFor(function()
	for _, event in ipairs(replayed) do if event.path:sub(-8) == "note.txt" and event.removed then return true end end
end), "a watch started from an earlier event ID replays later changes")
replay.cancel()
os.execute("/bin/rm -rf " .. root)
os.exit(t.summary() and 0 or 1)
