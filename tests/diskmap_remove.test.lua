_G.__headless = true
local t = require("TestKit")
local Harness = require("tests.support.diskmap")
local Items = require("apps.diskmap.models.Items")
local Remove = require("apps.diskmap.flows.Remove")

-- Review, act, confirm (VISION.md promise 3): nothing moves until the
-- person confirms, each item is checked again just before it goes, and a
-- history of what moved is written.
local host = Harness.env()
local service, home = host.service, host.env.model.home
local fixture = service.fixture
local freeBefore = service.diskSpace().freeKb
local function item(path) return Items:byPath(path) end

-- The confirmation names every item and what happens to it.
local title, message = Remove.confirmation({item(home .. "/Developer/meadow/build"), Items:find("runtime:A1B2C3D4-0002-4000-8000-000000000002"), item(home .. "/Developer/webshop/.claude/worktrees/checkout-flow-1a2b")})
t.assertEqual(title, "Remove 3 Items", "a batch is titled by its count")
t.expect(message:find("CMake build · meadow (480.0 MB) · Move to Trash", 1, true) and message:find("iOS 18.5 (7.2 GB) · Delete Runtime", 1, true), "each item has its verb")
t.expect(message:find("simctl", 1, true) and message:find("git worktree remove", 1, true) and message:find("put them back", 1, true), "the verbs are explained")
t.assertEqual((Remove.confirmation({item(home .. "/Developer/meadow/build")})), "Move to Trash", "one item is titled by its verb")

-- A kept item is never part of a bulk removal.
local Keeps = require("apps.diskmap.models.Keeps")
Keeps:toggle(home .. "/Library/Developer/Xcode/DerivedData/SymbolCache.noindex")

-- Declining the confirmation removes nothing.
local overview = Harness.mount("overview", host)
fixture.confirm = false
t.expect(not overview.actions.removeSafe(), "declining removes nothing")
t.assertEqual(service.diskSpace().freeKb, freeBefore, "and changes nothing on disk")
t.assertEqual(#service.operationLog(), 0, "and logs nothing")

-- The run: Chrome is open, so its cache is skipped; a build folder whose
-- project file went is skipped; everything else goes its own way.
local safe = 0
for _, row in ipairs(Items:all()) do if row.verdict == "safe" and Remove.allowed(row) then safe = safe + 1 end end
fixture.confirm = true
fixture.running["com.google.Chrome"] = true
service.trash(home .. "/Developer/meadow/CMakeLists.txt")
t.expect(overview.actions.removeSafe(), "the removal runs")
local notice = host.presented.notice
t.expect(notice:find("moved to the Trash", 1, true), "the notice says what moved")
t.expect(notice:find("skipped because Google Chrome was open", 1, true), "an open app's cache is skipped and named")
t.expect(notice:find("skipped because the project file that identified it is gone", 1, true), "a build folder without its proof is skipped")
t.expect(notice:find("Free before", 1, true), "free space before and after is reported")
t.assertEqual(host.presented.hidden.notice, false, "the notice is shown")
t.expect(service.diskSpace().freeKb > freeBefore + 20e9 / 1024, "the fixture freed what moved")
t.assertEqual(item(home .. "/Library/Developer/Xcode/DerivedData/Tidepool-abcdefghijklmnopqrstuvwxyzabcd"), nil, "a moved item leaves the model without measuring again")
t.expect(item(home .. "/Library/Caches/com.google.Chrome") ~= nil, "a skipped item stays")
t.expect(item(home .. "/Developer/meadow/build") ~= nil, "a skipped build folder stays")
t.assertEqual(Items:find("runtime:A1B2C3D4-0002-4000-8000-000000000002"), nil, "a runtime was deleted through simctl")
t.assertEqual(Items:find("5C2E0F4A-3B5D-4C7E-8F9A-2B3C4D5E6F7A"), nil, "an unavailable device was deleted through simctl")
t.assertEqual(item(home .. "/Developer/webshop/.claude/worktrees/checkout-flow-1a2b"), nil, "a worktree was removed through git")
t.expect(not fixture:exists(home .. "/Developer/webshop/.claude/worktrees/checkout-flow-1a2b"), "and its files are gone")
local log = service.operationLog()
t.assertEqual(#log, safe, "every item, moved or skipped, is logged once")
local verbs = {}
for _, line in ipairs(log) do verbs[line:match("^[^\t]*\t([^\t]*)")] = true end
t.expect(verbs["Move to Trash"] and verbs["Delete Runtime"] and verbs["Remove Worktree"] and verbs["Delete"], "the log names each kind of action")
local history = Harness.mount("history", host)
t.assertEqual(history.refs.entries.rowCount, safe, "Action History shows every action")
t.expect(host.presented.subtitle:find("operations.log", 1, true), "and says where the log is")

-- One row from its page: erase keeps the device and empties it.
local simulators = Harness.mount("simulators", host)
local ipad = Items:find("7B3D1E5F-2A4C-4B6D-9E7F-1A2B3C4D5E6F")
t.expect(simulators.actions.removeRow(nil, nil, {id = ipad.id}), "erasing runs from the row")
local after = Items:find("7B3D1E5F-2A4C-4B6D-9E7F-1A2B3C4D5E6F")
t.expect(after ~= nil and after.bytes == 0, "the erased device stays, empty")

-- A running simulator is refused at the last check; a dirty worktree and a
-- kept item are never offered.
local iphone = Items:find("9A4C2D7E-1F3B-4A5C-8D6E-0F1A2B3C4D5E")
fixture.simulators.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"][1].state = "Booted"
simulators.actions.removeRow(nil, nil, {id = iphone.id})
t.expect(host.presented.notice:find("Shut down the simulator", 1, true), "a device booted since it was listed is skipped")
local dirty = item(home .. "/.codex/worktrees/cart-fix/webshop")
local ok, why = Remove.allowed(dirty)
t.expect(not ok and why:find("uncommitted change", 1, true), "a worktree with changes cannot be removed, and says why")
local kept = Harness.mount("xcode", host)
local rows = host.lists.list_derived
local symbolCache
for _, row in ipairs(rows) do if row.name == "Symbol cache" then symbolCache = row end end
t.expect(symbolCache.removable == false and symbolCache.verdict == "keep", "a kept item cannot be removed")
local removed = 0
for _, row in ipairs(Items:inCategory("xcode")) do if row.verdict == "safe" and Remove.allowed(row) then removed = removed + 1 end end
t.assertEqual(removed, 0, "nothing safe is left on the Xcode page after the run")
t.expect(not kept.actions.removeSafe(), "so Remove Safe Items does nothing")

-- The Folder Map removes items in the home folder, never a standard folder.
local folder = Harness.mount("folder", host, {path = home .. "/Developer"})
folder.actions.removeRow(nil, nil, {id = home .. "/Developer/tooling", path = home .. "/Developer/tooling", name = "tooling", bytes = 1, directory = true})
t.expect(not fixture:exists(home .. "/Developer/tooling"), "a folder in the home folder can be removed from the map")
t.expect(host.presented.notice:find("moved to the Trash", 1, true), "and the map says so")
folder = Harness.mount("folder", host, {path = home})
local errors = #fixture.errors
folder.actions.removeRow(nil, nil, {id = home .. "/Library", path = home .. "/Library", name = "Library", bytes = 1, directory = true})
t.expect(fixture:exists(home .. "/Library") and #fixture.errors == errors + 1, "a standard folder is refused with an explanation")

os.exit(t.summary() and 0 or 1)
