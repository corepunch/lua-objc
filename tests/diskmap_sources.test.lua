_G.__headless = true
local t = require("TestKit")
local Harness = require("tests.support.diskmap")
local Items = require("apps.diskmap.models.Items")
local Categories = require("apps.diskmap.models.Categories")
local Sources = require("apps.diskmap.services.Sources")

-- Every source over the synthetic Mac: what it finds, and the verdicts it
-- computes from conventions and measurements, never from guesses.
local host = Harness.env()
local home = host.env.model.home
local function item(path) return Items:byPath(path) end
local function row(id) return Items:find(id) end

for _, category in ipairs(Categories:all()) do
	local rows = category:items()
	t.expect(#rows > 0, category.id .. " found rows")
	for _, r in ipairs(rows) do
		t.expect(type(r.name) == "string" and type(r.owner) == "string" and type(r.what) == "string", category.id .. ": " .. r.id .. " says what it is and whose")
		t.expect(r.verdict and r.reason and r.action, category.id .. ": " .. r.id .. " has a verdict, a reason and an action")
		t.expect(r.state ~= "measured" or r.bytes ~= nil, category.id .. ": " .. r.id .. " is measured")
	end
end
t.assertEqual(host.env.model.scan.running, false, "the measurement finished")

-- Xcode: the newest device support per platform is kept, older ones are
-- safe; DerivedData of a missing project is safe, of a present one yours.
local support = Items:inSection("xcode", "support")
t.assertEqual(#support, 4, "four device support versions")
t.assertEqual(item(home .. "/Library/Developer/Xcode/iOS DeviceSupport/iPhone16,2 26.0.1 (23A350)").verdict, "keep", "the newest iOS version is kept")
t.assertEqual(item(home .. "/Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)").verdict, "safe", "an older iOS version is safe")
t.assertEqual(item(home .. "/Library/Developer/Xcode/watchOS DeviceSupport/Watch7,4 26.0 (23R356)").verdict, "keep", "each platform keeps its newest")
local tidepool = item(home .. "/Library/Developer/Xcode/DerivedData/Tidepool-abcdefghijklmnopqrstuvwxyzabcd")
t.assertEqual(tidepool.verdict, "safe", "build data of a project that no longer exists is safe")
t.expect(tidepool.reason:find("no longer exists", 1, true), "and says so")
t.assertEqual(item(home .. "/Library/Developer/Xcode/DerivedData/Birdsong-fxkqwrtyuiopasdfghjklzxcvbnmqw").verdict, "review", "build data of a present project is a decision")
t.assertEqual(item(home .. "/Library/Developer/Xcode/DerivedData/ModuleCache.noindex").name, "Module cache", "shared caches are named for what they hold")
local archives = Items:inSection("xcode", "archives")
t.assertEqual(#archives, 2, "archives are found under their day folders")
local oldest
for _, archive in ipairs(archives) do if archive.date == "2026-06-14" then oldest = archive end end
t.expect(oldest and oldest.verdict == "review" and oldest.detail == "Version 1.4 (140)", "archives carry their version and are never safe")
t.assertEqual(item("/Library/Developer/CommandLineTools").admin, true, "root-owned folders are marked")
t.assertEqual(item("/Library/Developer/CommandLineTools").action, "none", "and Diskmap does not offer to move them")

-- Simulators: unavailable and unlisted devices are safe; a runtime without
-- devices is safe; a non-deletable one is kept.
local iphone15 = row("5C2E0F4A-3B5D-4C7E-8F9A-2B3C4D5E6F7A")
t.expect(iphone15.verdict == "safe" and iphone15.action == "delete", "a device without its runtime is safe to delete")
local orphan = row("1E0A8D2C-5D7F-4E9A-8B1C-4D5E6F7A8B9C")
t.expect(orphan.verdict == "safe" and orphan.name == "iPhone SE (3rd generation)", "a folder simctl no longer lists is safe and named from its plist")
local ipad = row("7B3D1E5F-2A4C-4B6D-9E7F-1A2B3C4D5E6F")
t.expect(ipad.verdict == "review" and ipad.action == "erase" and ipad.reason:find("Not booted for", 1, true), "a stale device is a decision, with erase offered")
t.assertEqual(row("runtime:A1B2C3D4-0002-4000-8000-000000000002").verdict, "safe", "a runtime with no devices is safe")
t.assertEqual(row("runtime:A1B2C3D4-0001-4000-8000-000000000001").verdict, "review", "a runtime with devices is a decision")
t.assertEqual(row("runtime:A1B2C3D4-0003-4000-8000-000000000003").verdict, "keep", "a runtime simctl cannot delete is kept")
t.assertEqual(item("/Library/Developer/CoreSimulator/Caches").verdict, "safe", "the simulator's dyld cache is safe")

-- Projects: a proven, idle build folder is safe; a proven, active one and
-- an unproven one are decisions.
local meadow = item(home .. "/Developer/meadow/build")
t.expect(meadow and meadow.verdict == "safe" and meadow.name == "CMake build · meadow", "a CMake build idle for months is safe")
t.expect(meadow.reason:find("Last built 9 months ago", 1, true), "and says when it was built")
t.assertEqual(item(home .. "/Developer/webshop/node_modules").verdict, "safe", "stale node_modules are safe")
t.assertEqual(item(home .. "/Developer/rustle/target").verdict, "review", "a build used this week is a decision")
local tooling = item(home .. "/Developer/tooling/build")
t.expect(tooling.verdict == "review" and tooling.reason:find("Nothing inside proves", 1, true), "an unproven build folder is a decision")
t.expect(item(home .. "/Developer/Birdsong/Build").reason:find("older than its sources", 1, true), "a build older than its sources says so")
t.assertEqual(item(home .. "/Developer/webshop/.claude/worktrees/checkout-flow-1a2b/node_modules"), nil, "nothing inside a worktree counts as a project build")

-- Worktrees: merged and published is safe; dirty, unpublished and recent
-- are decisions; a missing registration is pruned.
local ready = item(home .. "/Developer/webshop/.claude/worktrees/checkout-flow-1a2b")
t.expect(ready.verdict == "safe" and ready.action == "worktreeRemove" and ready.owner == "Claude", "a clean, published worktree is safe to remove")
t.expect(ready.reason:find("merged into origin/main", 1, true), "and says its commits are merged")
t.assertEqual(item(home .. "/.codex/worktrees/cart-fix/webshop").verdict, "review", "a worktree with changes is a decision")
t.assertEqual(item(home .. "/Developer/rustle-experiment").detail, "Local commits", "unpublished commits are named")
local gone = item(home .. "/Developer/webshop/.claude/worktrees/gone-9f8e")
t.expect(gone.action == "worktreePrune" and gone.section == "missing", "a missing worktree is pruned")

-- Editors: an older version beside a newer one is a leftover.
t.assertEqual(item(home .. "/.vscode/extensions/vadimcn.vscode-lldb-1.10.0").verdict, "safe", "an older extension version is safe")
t.assertEqual(item(home .. "/.vscode/extensions/vadimcn.vscode-lldb-1.11.0").verdict, "review", "the newest version stays")
t.assertEqual(item(home .. "/Library/Application Support/Claude/claude-code/2.1.293").verdict, "safe", "an older bundled CLI is safe")
t.assertEqual(item(home .. "/Library/Caches/JetBrains/CLion2024.3").verdict, "safe", "IDE caches are safe")

-- AI tools: children of a tool's folder carry their own notes.
local sessions = item(home .. "/.codex/sessions")
t.expect(sessions.verdict == "review" and sessions.what:find("Conversation transcripts", 1, true), "Codex sessions are a decision")
t.assertEqual(item(home .. "/.codex/log").verdict, "safe", "Codex logs are safe")
t.assertEqual(item(home .. "/.cache/codex-runtimes").verdict, "safe", "a downloaded runtime is safe")
t.assertEqual(item(home .. "/.ollama/models").verdict, "owner", "models are removed with their tool")
t.assertEqual(item(home .. "/Library/Caches/com.openai.codex").category, "ai", "a cache the AI page lists is not repeated under System Data")

-- System Data: volumes by their own size; caches by owner, honestly.
t.assertEqual(row("volume:Preboot").bytes, 10.9e9, "Preboot is measured by its volume")
t.assertEqual(row("volume:VM").verdict, "system", "swap is macOS's")
local chrome = item(home .. "/Library/Caches/com.google.Chrome")
t.expect(chrome.owner == "Google Chrome" and chrome.verdict == "safe" and chrome.bundleId == "com.google.Chrome", "an installed app's cache is safe and names its app")
local unclaimed = item(home .. "/Library/Caches/com.oldvendor.gone")
t.expect(unclaimed.verdict == "review" and unclaimed.reason:find("Not part of macOS", 1, true) and unclaimed.owner == "No installed app", "an unclaimed cache is a decision and says it is not macOS's")
t.assertEqual(item(home .. "/Library/Caches/com.apple.Music").verdict, "system", "Apple's caches are macOS's")
t.assertEqual(item(home .. "/Library/Caches/GeoServices").verdict, "system", "an Apple service's cache is macOS's")
t.assertEqual(item("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Siri_Understanding").name, "Siri understanding", "asset classes read by name")
t.assertEqual(item("/System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation").verdict, "owner", "documentation is removed in Xcode")
t.assertEqual(item("/private/tmp/build-cache-x").verdict, "review", "temporary files are a decision")
t.assertEqual(item("/private/var/folders/fg/z7bvq7qs1lvfv6mdjsnr5gz40000gn/C/clang").verdict, "safe", "the clang module cache is safe")

-- Totals: safe bytes are a subset, and the Overview's bar never exceeds the disk.
local bytes, safe = Items:totals("xcode")
t.expect(safe > 0 and safe < bytes, "safe bytes are part of the total")
Harness.mount("overview", host)
local total = 0
for _, segment in ipairs(host.presented.segments) do total = total + segment.value end
t.expect(total <= host.presented.total, "the bar's segments fit the disk")
t.expect(host.presented.headline:find("can go now", 1, true), "the headline says what can go")

-- Measuring again replaces rows without losing Keep.
local Keeps = require("apps.diskmap.models.Keeps")
Keeps:toggle(ipad.id)
host.env.sources:run({"simulators"})
local presented = host.env:page("simulators"):flow("Rows"):present(Items:inSection("simulators", "devices"))
local keptRow
for _, r in ipairs(presented) do if r.id == ipad.id then keptRow = r end end
t.expect(keptRow and keptRow.verdict == "keep" and keptRow.removable == false, "a kept device stays kept after measuring again, and cannot be removed")
t.expect(Sources.olderVersions({{name = "a-1.2.0"}, {name = "a-1.10.0"}, {name = "b"}})["a-1.2.0"] == "a-1.10.0", "versions compare numerically")

os.exit(t.summary() and 0 or 1)
