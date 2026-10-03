_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Store = require("apps.diskmap.Store")
local Host = require("tests.diskmap_page")
local Plan = require("apps.diskmap.helpers.SimulatorPlan")
local Simulators = require("apps.diskmap.helpers.Simulators")

local TYPE = "com.apple.CoreSimulator.SimDeviceType."
local RT26 = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
local RT18 = "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
local WATCH = "com.apple.CoreSimulator.SimRuntime.watchOS-26-0"
local NOW = os.time({year = 2026, month = 10, day = 1, hour = 12})

local function device(id, name, deviceType, extra)
	local row = {name = name, udid = id, state = "Shutdown", isAvailable = true, lastUsedAt = "2026-09-20T16:20:00Z",
		deviceType = TYPE .. deviceType, dataPathSize = 1e9, dataPath = "/d/" .. id .. "/data"}
	for key, value in pairs(extra or {}) do row[key] = value end
	return row
end
local function inventory(devices)
	local runtimes = {}
	for identifier in pairs(devices) do table.insert(runtimes, {identifier = identifier, name = identifier}) end
	table.sort(runtimes, function(a, b) return a.identifier < b.identifier end)
	return {runtimes = runtimes, devices = devices}
end
local function uid(n) return string.format("%08d-0000-4000-8000-%012d", n, n) end
local function plan(devices, options)
	options = options or {}
	return Plan.build(inventory(devices), options)
end
local function roles(p)
	local result = {}
	for _, entry in ipairs(p.devices) do result[entry.id] = entry.role end
	return result
end

-- Models come from the device type, never from the editable name.
t.assertEqual(select(1, Plan.classify(TYPE .. "iPhone-17")), "iPhone", "iPhone-17 is an iPhone")
t.expect(select(2, Plan.classify(TYPE .. "iPhone-17")), "iPhone-17 is a base model")
for _, variant in ipairs({"iPhone-17-Pro", "iPhone-17-Pro-Max", "iPhone-Air", "iPhone-16e", "iPhone-SE-3rd-generation"}) do
	t.expect(not select(2, Plan.classify(TYPE .. variant)), variant .. " is not a base model")
	t.assertEqual(select(1, Plan.classify(TYPE .. variant)), "iPhone", variant .. " is still an iPhone")
end
t.expect(select(2, Plan.classify(TYPE .. "iPad-10th-generation")), "iPad-10th-generation is the base iPad")
t.expect(select(2, Plan.classify(TYPE .. "iPad-A16")), "iPad-A16 is the base iPad")
for _, variant in ipairs({"iPad-Pro-13-inch-M5", "iPad-Air-11-inch-M3", "iPad-mini-A17-Pro"}) do
	t.expect(not select(2, Plan.classify(TYPE .. variant)), variant .. " is not a base iPad")
end
t.assertEqual(Plan.classify(TYPE .. "Apple-Watch-Series-11-46mm"), nil, "a watch belongs to neither family")
t.assertEqual(Plan.classify(nil), nil, "a missing device type belongs to no family")

-- A custom name does not change the model: a base iPhone named "Pro Max".
local named = plan({[RT26] = {
	device(uid(1), "iPhone 17 Pro Max", "iPhone-17"),
	device(uid(2), "My Test Phone", "iPhone-17-Pro-Max"),
	device(uid(3), "iPad", "iPad-A16"),
	device(uid(4), "Standard iPad", "iPad-Pro-13-inch-M5"),
}})
t.assertEqual(named.keep.iPhone, uid(1), "the base model is kept even when named like a Pro Max")
t.assertEqual(named.keep.iPad, uid(3), "the base iPad is kept even when a Pro is named Standard")
t.assertEqual(#named.removal, 2, "the other two devices are proposed for removal")
t.expect(named.ready and named.complete, "the plan is ready and complete")

-- Duplicate base models: the most recently used one is kept; ties keep more data.
local dup = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17", {lastUsedAt = "2026-08-01T10:00:00Z"}),
	device(uid(2), "iPhone 17 (2)", "iPhone-17", {lastUsedAt = "2026-09-25T10:00:00Z"}),
	device(uid(3), "iPhone 17 (3)", "iPhone-17", {lastUsedAt = "2026-09-25T10:00:00Z", dataPathSize = 5e9}),
	device(uid(4), "iPad", "iPad-A16"),
}})
t.assertEqual(dup.keep.iPhone, uid(3), "the newest duplicate with the most data is kept")
t.assertEqual(roles(dup)[uid(1)], "remove", "older duplicates are redundant")

-- Multiple runtimes: the newest iOS runtime is the default and other runtimes' devices are reviewed.
local multi = plan({
	[RT26] = {device(uid(1), "iPhone 17", "iPhone-17"), device(uid(2), "iPad", "iPad-A16")},
	[RT18] = {device(uid(3), "iPhone 16", "iPhone-16"), device(uid(4), "iPad 18", "iPad-A16")},
	[WATCH] = {device(uid(5), "Watch", "Apple-Watch-Series-11-46mm")},
})
t.assertEqual(multi.runtime, RT26, "the newest iOS runtime is chosen by default")
t.assertEqual(multi.runtimes[2].identifier, RT18, "other iOS runtimes are offered")
t.assertEqual(roles(multi)[uid(3)], "remove", "a device on another runtime is reviewed and proposed")
t.assertEqual(roles(multi)[uid(5)], "outside", "a watch is outside the plan, not removed")
t.assertEqual(#multi.devices, 5, "every device is in the review")
t.assertEqual(multi.runtimePreserved, RT26, "the runtime of the kept devices is preserved")
local chosen = plan({
	[RT26] = {device(uid(1), "iPhone 17", "iPhone-17"), device(uid(2), "iPad", "iPad-A16")},
	[RT18] = {device(uid(3), "iPhone 16", "iPhone-16"), device(uid(4), "iPad 18", "iPad-A16")},
}, {runtime = RT18})
t.assertEqual(chosen.keep.iPhone, uid(3), "choosing a runtime keeps its devices")
t.assertEqual(roles(chosen)[uid(1)], "remove", "and proposes the others")

-- Missing metadata stays unknown and blocks rather than guessing.
local missing = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17"),
	device(uid(2), "Unknown State", "iPhone-17-Pro", {state = false}),
	device(uid(3), "No Usage", "iPhone-17-Pro", {lastUsedAt = false}),
	device(uid(4), "iPad", "iPad-A16"),
}})
-- state=false is not a string, so Simulators.rows leaves running unknown
t.assertEqual(roles(missing)[uid(2)], "blocked", "a device whose state is unknown is blocked, not removed")
t.assertEqual(roles(missing)[uid(3)], "remove", "missing usage does not stop a proposal")
local usage
for _, entry in ipairs(missing.devices) do if entry.id == uid(3) then usage = entry.lastUse end end
t.assertEqual(usage, "Last use unknown", "and the missing date reads unknown")
t.assertEqual(missing.blockedBytes, 1e9, "blocked bytes are counted apart")
t.assertEqual(missing.removalBytes, 1e9, "removal bytes cover only eligible devices")

-- Running devices need shutdown first.
local running = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17"), device(uid(2), "iPad", "iPad-A16"),
	device(uid(3), "Booted", "iPhone-17-Pro", {state = "Booted"}),
}})
t.assertEqual(roles(running)[uid(3)], "blocked", "a running device is blocked")
t.expect(running.devices[3] and #running.removal == 0, "nothing is eligible while the only extra is running")
t.expect(not running.ready, "so the plan is not ready")

-- Keep protection and user-preserved QA devices survive.
local protected = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17"), device(uid(2), "iPad", "iPad-A16"),
	device(uid(3), "QA phone", "iPhone-17-Pro"), device(uid(4), "Locked", "iPhone-17-Pro-Max"),
}}, {preserve = {[uid(3)] = true}, protected = function(id) return id == uid(4) end})
t.assertEqual(roles(protected)[uid(3)], "preserve", "a specialised QA device is preserved")
t.assertEqual(roles(protected)[uid(4)], "preserve", "a Keep-protected device is preserved")
t.assertEqual(#protected.removal, 0, "preserved devices are not removed")
t.assertEqual(protected.preservedBytes, 2e9, "preserved bytes are counted apart")

-- An unavailable base model is not a keeper; with no standard device a choice is required.
local noBase = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17", {isAvailable = false}),
	device(uid(2), "iPhone 17 Pro", "iPhone-17-Pro"),
	device(uid(3), "iPad", "iPad-A16"),
}})
t.assertEqual(noBase.keep.iPhone, nil, "an unavailable base model is not kept")
t.expect(noBase.needsChoice.iPhone and not noBase.needsChoice.iPad, "the iPhone family needs a choice")
t.expect(not noBase.complete, "the plan is incomplete")
t.assertEqual(roles(noBase)[uid(2)], "undecided", "no iPhone is proposed for removal until one is chosen")
t.assertEqual(#noBase.removal, 0, "nothing is silently removed")

-- A user override replaces the proposal; an invalid override is ignored.
local override = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17"), device(uid(2), "iPhone 17 Pro", "iPhone-17-Pro"), device(uid(3), "iPad", "iPad-A16"),
}}, {keep = {iPhone = uid(2)}})
t.assertEqual(override.keep.iPhone, uid(2), "the user's keep choice is honoured")
t.assertEqual(roles(override)[uid(1)], "remove", "and the proposed device is now redundant")
local bad = plan({[RT26] = {
	device(uid(1), "iPhone 17", "iPhone-17"), device(uid(2), "iPad", "iPad-A16"),
}}, {keep = {iPhone = uid(2)}})
t.assertEqual(bad.keep.iPhone, uid(1), "an iPad cannot be chosen as the iPhone")
local chosenFromNoBase = plan({[RT26] = {
	device(uid(1), "iPhone 17 Pro", "iPhone-17-Pro"), device(uid(2), "iPhone 17 Pro Max", "iPhone-17-Pro-Max"), device(uid(3), "iPad", "iPad-A16"),
}}, {keep = {iPhone = uid(1)}})
t.expect(chosenFromNoBase.complete and #chosenFromNoBase.removal == 1, "choosing a keeper completes the plan")

-- Each device counts once; the kept pair is never in the removal set.
local totals = plan({[RT26] = {
	device(uid(1), "iPhone", "iPhone-17"), device(uid(2), "iPad", "iPad-A16"),
	device(uid(3), "a", "iPhone-17-Pro", {dataPathSize = 2e9}), device(uid(4), "b", "iPad-mini-A17-Pro", {dataPathSize = 3e9}),
}})
t.assertEqual(totals.removalBytes, 5e9, "removal bytes add each device once")
t.assertEqual(totals.keepBytes, 2e9, "kept bytes are separate")
local ids = {}
for _, entry in ipairs(totals.removal) do ids[entry.id] = true end
t.expect(not ids[uid(1)] and not ids[uid(2)], "the kept pair is not in the removal set")

-- Revalidation: a kept device, an unplanned device and a now-running device are refused.
local ok = Plan.revalidate(totals, uid(3), {id = uid(3), running = false, available = true})
t.expect(ok, "a planned, shut-down device passes")
t.expect(not Plan.revalidate(totals, uid(1), {id = uid(1), running = false, available = true}), "the kept iPhone is refused")
t.expect(not Plan.revalidate(totals, uid(99), {id = uid(99), running = false}), "a device outside the plan is refused")
t.expect(not Plan.revalidate(totals, uid(3), {id = uid(3), running = true, available = true}), "a device that started running is refused")
t.expect(not Plan.revalidate(totals, uid(3), nil), "a device that vanished is refused")
t.expect(Plan.confirmation(totals):find("Delete 2 simulators", 1, true), "the confirmation names the whole removal set")

-- Empty inventory.
local empty = Plan.build({runtimes = {}, devices = {}}, {})
t.expect(not empty.ready and #empty.devices == 0 and empty.runtime == nil, "no devices means no plan")

-- The page: the plan renders, batch deletion revalidates each device, spares the
-- kept pair and the runtime, reports skips and failures, and continues past them.
local function udid(n) return string.format("%08X-0000-4000-8000-%012X", n, n) end
local rtId = RT26
local fixture = {
	[udid(1)] = {name = "Phone", type = "iPhone-17", state = "Shutdown", bytes = 2e9, used = "2026-09-29T10:00:00Z"},
	[udid(2)] = {name = "Pad", type = "iPad-A16", state = "Shutdown", bytes = 1e9, used = "2026-09-20T10:00:00Z"},
	[udid(3)] = {name = "Extra A", type = "iPhone-17-Pro", state = "Shutdown", bytes = 3e9, used = "2026-08-01T10:00:00Z"},
	[udid(4)] = {name = "Extra B", type = "iPhone-17-Pro-Max", state = "Shutdown", bytes = 4e9, used = "2026-07-01T10:00:00Z"},
	[udid(5)] = {name = "Extra C", type = "iPad-mini-A17-Pro", state = "Shutdown", bytes = 5e9},
}
local deletions, confirmations, saved = {}, {}, nil
local failOn
local service = {
	home = "/Users/test",
	children = function()
		local list = {}
		for id, record in pairs(fixture) do table.insert(list, {name = id, path = "/Users/test/Devices/" .. id, bytes = record.bytes}) end
		return list
	end,
	readPropertyList = function(path)
		local record = fixture[path:match("Devices/([^/]+)")]
		return record and {name = record.name, runtime = rtId, deviceType = TYPE .. record.type, lastBootedAt = record.used}
	end,
	simulatorDevices = function(done)
		local list = {}
		for id, record in pairs(fixture) do table.insert(list, {udid = id, name = record.name, state = record.state, isAvailable = true, deviceTypeIdentifier = TYPE .. record.type}) end
		done({devices = {[rtId] = list}})
	end,
	simulatorRuntimes = function(done) done({}) end,
	simulatorState = function(id, done)
		local record = fixture[id]
		done(record and {udid = id, state = record.state, isAvailable = true} or nil)
	end,
	command = function(argv, done)
		table.insert(deletions, argv[4])
		if argv[4] == failOn then done(false, "simctl failed"); return end
		fixture[argv[4]] = nil
		done(true, "")
	end,
	confirmAction = function(title, message) table.insert(confirmations, message); return true end,
	saveKeep = function(kept) saved = kept; return true end,
	reveal = function() end,
	openOwner = function() end,
	measure = function(paths, done) local sizes = {} for i in ipairs(paths) do sizes[i] = 0 end done(sizes) end,
}
local changed = 0
local storage = Store.new("/Users/test")
local page, model = Host.new("simulators", {model = storage, service = service,
	rescan = function() error("deleting devices never measures the disk again") end, removed = function() changed = changed + 1 end})
page:mount(ns.VStack {}, {query = ""})
local refs = page.refs
t.expect(refs and refs.planDevices, "the minimal device set renders on the Simulators page")
t.assertEqual(refs.planDevices.rowCount, 5, "every device is in the plan list")
t.assertEqual(model:plan().keep.iPhone, udid(1), "the base iPhone is proposed")
t.assertEqual(model:plan().keep.iPad, udid(2), "the base iPad is proposed")
t.expect(refs.planReview.enabled, "a ready plan can be reviewed")
t.expect(refs.planReview.title:find("3 Devices", 1, true), "the button counts the removal set")
t.assertEqual(refs.planAmount.text, "12.0 GB", "the amount beside the review button totals the removal set")
t.assertEqual(refs.planCaption.text, "could recover", "and says it is what the plan could recover")
t.expect(refs.planHeadline.text:find("delete 3 redundant devices", 1, true) ~= nil, "the headline states the decision: " .. refs.planHeadline.text)

-- Keep protection for one device removes it from the set; the choice persists.
model.planSelected = {id = udid(5), family = "iPad", runtimeIdentifier = rtId, available = true}
page.actions.planPreserve()
t.expect(saved and saved["simulator:" .. udid(5)], "Keep for a device is saved with the other Keep choices")
t.assertEqual(#model:plan().removal, 2, "a protected device leaves the removal set")
t.assertEqual(page.refs.planPreserve.title, "Remove Keep", "and the button offers to undo it")
model.planSelected = nil
model:planKeepThis()

-- A device that started running after the plan was drawn is skipped, a failing
-- delete is reported, and the rest still go through.
fixture[udid(3)].state = "Booted"
failOn = udid(4)
storage.kept["simulator:" .. udid(5)] = true
local ran = model:planReview()
t.expect(ran, "review runs after one confirmation")
t.assertEqual(#confirmations, 1, "the whole removal set is confirmed once")
t.expect(confirmations[1]:find("Extra A", 1, true) and confirmations[1]:find("Extra B", 1, true), "the confirmation lists the removal set")
t.expect(not confirmations[1]:find("Extra C", 1, true), "a protected device is not in the confirmation")
t.expect(not confirmations[1]:find("Phone", 1, true) or confirmations[1]:find("Kept: Phone", 1, true), "the kept devices are named as kept")
t.assertEqual(deletions[1], udid(4), "the only still-eligible device is attempted")
t.assertEqual(#deletions, 1, "the device that began running was never deleted")
t.expect(fixture[udid(3)] and fixture[udid(1)] and fixture[udid(2)] and fixture[udid(5)], "kept, protected and running devices survive")
t.expect(model.planResult:find("Skipped", 1, true) and model.planResult:find("Failed", 1, true), "skips and failures are reported separately: " .. tostring(model.planResult))
t.assertEqual(page.refs.planStatus.text, model.planResult, "and the page states them")
t.assertEqual(changed, 0, "a device that failed to delete stays in the model")
os.exit(t.summary() and 0 or 1)
