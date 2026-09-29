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

t.expect(same(C.at("window", 1.234), C.at("window", 1.234)) and same(C.eye(9.87), C.eye(9.87)),
	"poses and the camera are pure functions of t")
for _, time in ipairs({ 0, 3, 6.5, 12, 13.5, 16, 19, 21, 21.79, 26, 29.9 }) do
	local eye, target, lens = C.camera(time)
	t.expect(Space.length3(Space.sub3(eye, target)) > 0.1 and lens > 10 and lens < 90,
		string.format("the camera has a sane lens and target at %.2f s", time))
end

-- The montage window lands exactly in the display's window slot: centred on
-- its screen and scaled so its 1200 pt fill 1200 of the screen's 1600 pt.
local slot = C.pose("window", S.landed)
local display = C.pose("display", S.landed)
local screenCentre = Space.transform({ 0, C.DEVICE.displayScreen.y, C.DEVICE.displayScreen.z }, display.position, display.rotation, 1)
t.expect(Space.length3(Space.sub3(slot.position, screenCentre)) < 0.02, "the window lands on the display's screen")
t.expect(near(slot.scale * C.DEVICE.window.w, C.DEVICE.displayScreen.w * 1200 / 1600, 1e-9), "at the window's size on that screen")
t.expect(near(slot.rotation[2] % 360, display.rotation[2] % 360, 1e-9), "facing the same way")

-- The phone leaves Lua Studio from the preview itself: at the lift it lies
-- on the iPad's screen at the preview's centre, turned with the iPad.
local lift = C.pose("phone", S.lift)
local previewCentre = C.padPoint(S.lift, C.PREVIEW.x + C.PREVIEW.w / 2, C.PREVIEW.y + C.PREVIEW.h / 2, 0.03)
t.expect(same(lift.position, previewCentre, 1e-9), "the phone starts at the preview's centre")
t.expect(same(lift.rotation, C.turn("pad", S.lift), 1e-9), "lying on the iPad's screen")
t.expect(near(lift.scale * C.DEVICE.phoneBody, C.PREVIEW.h / C.DEVICE.padScreen.points[2] * C.DEVICE.padScreen.h, 1e-9),
	"as tall as the preview")
t.expect(C.size("phone", S.free) == 1, "and is a real-sized phone once free")

-- The cut into the game: at the cut the camera looks straight into the game
-- phone's screen from the distance where the screen's height fills the
-- frame, with the lens the game camera continues with.
local eye, target, lens = C.camera(S.cut - 1e-6)
local centre, normal = C.gameScreen()
t.expect(same(target, centre, 1e-3), "the camera aims at the screen's centre at the cut")
local toEye = Space.normalize3(Space.sub3(eye, centre))
t.expect(same(toEye, normal, 1e-3), "square to the screen")
t.expect(near(Space.length3(Space.sub3(eye, centre)), C.cutDistance(), 1e-3), "at the distance that fills the frame")
t.expect(near(lens, C.CUT.fieldOfView, 1e-3), "with the lens the game continues with")
local frameHeight = 2 * C.cutDistance() * math.tan(math.rad(lens / 2))
t.expect(near(frameHeight, C.DEVICE.phoneScreen.w, 1e-6), "the screen's height is the frame's height")
t.expect(near(C.questCamera(S.cut).fieldOfView, C.CUT.fieldOfView, 1e-9), "the game camera starts with the same lens")

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
