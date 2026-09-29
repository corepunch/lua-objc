-- The promo reel's agent edits (reels/promo/Edits.lua, edits/*.patch):
-- every patch still reverse-applies to the app as it is in the repository,
-- in order, so each version the reel captures can be rebuilt; each patch
-- really changes its app; and the Lua Studio showcase built from them loads.
_G.__headless = true
package.path = "modules/reel/?.lua;reels/promo/?.lua;" .. package.path

local t = require("TestKit")
local Edits = require("Edits")
local Conversation = require("Conversation")

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local dir = os.tmpname()
os.remove(dir)

for name, app in pairs(Edits) do
	local root = dir .. "/" .. name
	os.execute("mkdir -p " .. quote(root .. "/demo") .. " && cp -R " .. quote(app.dir) .. " " .. quote(root .. "/" .. app.dir))
	for i = #app.edits, 1, -1 do
		local patch = "reels/promo/edits/" .. app.edits[i].patch .. ".patch"
		t.expect(io.open(patch) ~= nil, patch .. " exists")
		local ok = os.execute("patch -s -R -p1 --dry-run -d " .. quote(root) .. " < " .. quote(patch) .. " >/dev/null 2>&1")
		t.expect(ok, name .. ": " .. app.edits[i].patch .. " reverse-applies to version " .. i)
		os.execute("patch -s -R -p1 -d " .. quote(root) .. " < " .. quote(patch) .. " >/dev/null 2>&1")
		local file, added, removed = Conversation.summary(patch)
		t.expect(file and file:find(app.dir, 1, true) == 1, app.edits[i].patch .. " edits " .. app.dir)
		t.expect(added + removed > 0, app.edits[i].patch .. " changes lines")
		t.expect(app.edits[i].prompt:match("%.$") and #app.edits[i].reply > 0, app.edits[i].patch .. " has a prompt and a reply")
	end
	local same = os.execute("/usr/bin/diff -rq " .. quote(app.dir) .. " " .. quote(root .. "/" .. app.dir) .. " >/dev/null")
	t.expect(not same, name .. ": version 0 differs from the shipped app")
end

local lines = Conversation.lines("reels/promo/edits/todo-2-progress.patch")
t.assertEqual(lines[1].sign, " ", "diff lines keep context")
local added = 0
for _, line in ipairs(lines) do if line.sign == "+" then added = added + 1 end end
t.assertEqual(added, 10, "the progress edit adds ten lines")
t.expect(lines[4].text:find("^<GroupBox"), "indentation is folded away")

for k = 0, #Edits.todo.edits do
	local source = Conversation.showcase(Edits.todo, k, "reels/promo/edits/")
	local data = assert(load(source, "=showcase", "t", {}))()
	t.assertEqual(data.project, "demo/todo", "the showcase opens Todo (v" .. k .. ")")
	t.assertEqual(#data.conversation.messages, k * 2, "one exchange per edit so far (v" .. k .. ")")
	t.assertEqual(data.conversation.draft, Edits.todo.edits[k + 1] and Edits.todo.edits[k + 1].prompt or "",
		"the next prompt waits in the composer (v" .. k .. ")")
	for _, file in ipairs(data.files) do
		t.expect(io.open("demo/todo/" .. file) ~= nil, "showcase file demo/todo/" .. file .. " exists")
	end
end

os.execute("rm -rf " .. quote(dir))

-- ── Choreography: the places where two things must meet exactly ─────────

local C = require("Choreography")
local Space = require("reel.space")
local S = C.SHOT
local function near(a, b, e) return math.abs(a - b) <= (e or 1e-6) end
local function same(a, b, e) return near(a[1], b[1], e) and near(a[2], b[2], e) and near(a[3], b[3], e) end

t.expect(same(C.at("phone", 1.234), C.at("phone", 1.234)) and same(C.eye(9.87), C.eye(9.87)),
	"poses and the camera are pure functions of t")
for _, time in ipairs({ 0, 3, 4.6, 6.5, 8.2, 10.8, 12, 14, 16.5, 18, 19.59, 22, 25, 29.9 }) do
	local eye, target, lens = C.camera(time)
	t.expect(Space.length3(Space.sub3(eye, target)) > 0.1 and lens > 10 and lens < 90,
		string.format("the camera has a sane lens and target at %.2f s", time))
end

-- The camera holds still while a change lands on the phone and the next
-- prompt is sent: the two-shot from the first change to the second.
t.expect(same(C.eye(S.change1), C.eye(S.change2), 1e-9) and same(C.target(S.change1), C.target(S.change2), 1e-9),
	"the two-shot holds still through both changes")
-- The devices stand still while the story plays on their screens.
t.expect(same(C.at("pad", S.together), C.at("pad", S.noBuild), 1e-9), "the iPad holds its place")
t.expect(same(C.at("phone", S.together), C.at("phone", S.tap), 1e-9), "the phone holds its place")

-- Every event of the story is on the 120 BPM beat grid.
for _, name in ipairs({ "send1", "change1", "send2", "change2", "tap", "alone", "send3", "cut", "logo" }) do
	t.expect(near((S[name] * 2) % 1, 0, 1e-9), name .. " is on a beat")
end

-- The phone turned on its side is the game phone: the same place and the
-- same attitude (a portrait phone rolled a quarter turn is the landscape
-- build), so the swap cannot be seen.
local phone, game = C.pose("phone", S.swap), C.pose("game", S.swap)
t.expect(same(phone.position, game.position, 1e-9), "the game phone takes the phone's place")
for _, corner in ipairs({ { 0.3, 0.7, 0.04 }, { -0.3, -0.7, -0.04 } }) do
	local a = Space.transform(corner, phone.position, phone.rotation, 1)
	-- The landscape build lays the portrait's (x, y) at (-y, x).
	local b = Space.transform({ -corner[2], corner[1], corner[3] }, game.position, game.rotation, 1)
	t.expect(same(a, b, 1e-9), "and its attitude")
end

-- The cut into the game: at the cut the camera looks straight into the
-- game phone's screen from the distance where the screen's height fills the
-- frame, with the lens the game camera continues with.
local eye, target, lens = C.camera(S.cut - 1e-6)
local centre, normal = C.gameScreen()
t.expect(same(target, centre, 1e-3), "the camera aims at the screen's centre at the cut")
t.expect(same(Space.normalize3(Space.sub3(eye, centre)), normal, 1e-3), "square to the screen")
t.expect(near(Space.length3(Space.sub3(eye, centre)), C.cutDistance(), 1e-3), "at the distance that fills the frame")
t.expect(near(lens, C.CUT.fieldOfView, 1e-3), "with the lens the game continues with")
t.expect(near(2 * C.cutDistance() * math.tan(math.rad(lens / 2)), C.DEVICE.phoneScreen.w, 1e-6),
	"the screen's height is the frame's height")
t.expect(near(C.questCamera(S.cut).fieldOfView, C.CUT.fieldOfView, 1e-9), "the game camera starts with the same lens")

-- The Mac appears only in the closing composition.
local world = assert(io.open("reels/promo/views/World.etlua")):read("a")
local displays = 0
for _ in world:gmatch("devices/Display%.etlua") do displays = displays + 1 end
t.assertEqual(displays, 1, "one display in the world")
t.expect(world:find('id = "heroDisplay"', 1, true) and world:find("from=\"' .. S.hero", 1, true), "and it arrives with the close")

-- ── The Todo states the phone moves through ─────────────────────────────

local Todo = require("Todo")
local rows = Todo.states()
t.assertEqual(table.concat(rows.v0, ","), "1,2,3,4,5,6,7,8,9", "before the first edit every task shows in order")
t.assertEqual(table.concat(rows.v1, ","), "2,4,6,8,9,1,3,5,7", "grouped: open tasks, then completed")
t.assertEqual(table.concat(rows.checked, ","), "4,6,8,9,1,2,3,5,7", "the tapped task joins the completed")
t.assertEqual(table.concat(rows.filtered, ","), table.concat(rows.checked, ","), "it stays checked through the filter")
t.assertEqual(table.concat(rows.open, ","), "4,6,8,9", "Open hides completed tasks")
for _, state in ipairs(Edits.todo.states) do
	t.expect(rows[state.name] ~= nil, "the reel knows the captured state " .. state.name)
	for _, key in ipairs(state.changes) do
		t.expect(Edits.todo.changes[key] ~= nil, state.name .. " uses the defined change " .. key)
	end
end
-- Each change's text is still in the app, so the states can be captured.
local model = assert(io.open("demo/todo/Model.lua")):read("a")
for key, change in pairs(Edits.todo.changes) do
	t.expect(model:find(change.find, 1, true) ~= nil, "the change " .. key .. " still finds its text in the app")
end

-- ── Regions: components found in a screenshot ──────────────────────────

-- A synthetic Todo screenshot: white, a progress card in the grouped grey,
-- three rows with a divider under each, then a gap for the Completed label
-- and one more row.
local Reel = require("Reel")
local N = Reel.native()
local Regions = require("Regions")
local canvas = N.canvas(402, 874)
canvas:clear(1, 1, 1, 1)
canvas:fillRect(26, 150, 350, 70, 0.949, 0.949, 0.969, 1)
local dividers = { 290, 343, 396, 490 }
for _, y in ipairs(dividers) do canvas:fillRect(28, y, 346, 1, 0.85, 0.85, 0.85, 1) end
local shot = canvas:snapshot()
local parts = Regions.todo(shot, { 11, 12, 13, 14 })
t.expect(parts.progress and near(parts.progress.y, 148, 3) and near(parts.progress.h, 74, 4), "the progress card is found")
t.expect(parts.filter == nil, "a card is not taken for the filter")
t.expect(near(parts["task/13"].y + parts["task/13"].h - 1, 396, 1), "rows end at their dividers")
t.expect(near(parts["task/11"].h, 53, 1), "a row is as tall as the gap between dividers")
t.expect(parts.completed and parts.completed.y > 396 and parts.completed.y < 437, "a taller gap holds the Completed label")
t.assertThrows(function() Regions.todo(shot, { 1, 2 }) end, "rows that do not match the dividers are an error")

-- ── Coin Quest, replayed by the game's own model ────────────────────────

local CoinQuest = require("CoinQuest")
local script, at = {}, 1.25
for _, direction in ipairs({ "up", "left", "left", "left", "left", "left", "down", "down" }) do
	table.insert(script, { at, direction }); at = at + 0.21
end
local quest = CoinQuest.new({ level = 2, script = script, duration = 4 })
local again = CoinQuest.new({ level = 2, script = script, duration = 4 })
local coins = {}
for _, event in ipairs(quest.events) do if event.name == "coin" then table.insert(coins, event) end end
t.expect(#coins == 2 and not quest.hurt, "the scripted run takes two coins past the saws unhurt")
t.expect(near(coins[1].time, again.events[1].time, 0), "the replay is deterministic")
local p = quest:player(1.0)
t.expect(p[1] == 5 and p[3] == 3, "the player waits on the start cell before the first press")
local hopping = quest:player(1.33)
t.expect(hopping[2] > 0 and hopping[3] < 3 and hopping[3] > 2, "a hop is interpolated between cells, lifted on its arc")
local function pose(id, time)
	for _, entry in ipairs(quest:poses(time)) do if entry.id == id then return entry end end
end
t.expect(pose(coins[1].id, coins[1].time - 0.01) == nil, "a coin is untouched before it is taken")
t.expect(pose(coins[1].id, coins[1].time + 0.15).scale > 1, "a taken coin pops away")
t.expect(pose(coins[1].id, coins[1].time + 0.5).hidden, "and is gone")
t.expect(pose("flag", 1).hidden, "the flag waits hidden until the last coin")
local view = quest:view()
t.expect(view.flag ~= nil and #view.coins == 8 and view.level == "sawmill", "the stage template gets the level as it starts")
t.assertThrows(function() CoinQuest.new({ level = 1, script = { { 0, "sideways" } }, duration = 0.1 }) end,
	"an unknown direction is an error")

os.exit(t.summary() and 0 or 1)
