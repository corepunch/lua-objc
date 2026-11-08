_G.__headless = true

-- Lua Studio's Racing template (apps/studio/Documents/Games/Racing), run
-- the way Studio runs a project: through its Preview sandbox. Every track
-- loads and passes its checks; a broken track is a preview error naming the
-- problem; then the race plays headlessly: the countdown holds the cars,
-- the keys drive and steer, the grass slows the car, and an autopilot that
-- keeps to the road wins every race while the rivals finish behind it.

local t = require("TestKit")
local bridge = require("AppKitNative")
local AppKit = require("AppKit")
local Preview = require("apps.studio.services.Preview")

local ROOT = "apps/studio/Documents/Games/Racing/"
local function read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("a"); f:close(); return s
end

local metadata = assert(load(read(ROOT .. "project.lua"), "@project.lua", "t", {}))()
local function projectFiles()
	local files = {}
	for _, path in ipairs(metadata.files) do files["demo/playground/" .. path] = assert(read(ROOT .. path), path) end
	return files
end
t.expect(projectFiles()["demo/playground/AGENTS.md"] ~= nil, "the template carries its agent rulebook")

local templates = assert(load(read("apps/studio/Documents/templates.lua"), "@templates.lua", "t", {}))()
local listed = false
for _, entry in ipairs(templates) do if entry.id == "Racing" and entry.path == "Games/Racing" then listed = true end end
t.expect(listed, "the New Project sheet offers the Racing template")

local vocabulary = {}
for k, v in pairs(AppKit) do vocabulary[k] = v end
vocabulary.HostingController = function(content) return content end
local preview = Preview.new(vocabulary, read)

local content, err = preview:render(projectFiles())
t.expect(content ~= nil, "the template renders in Studio's preview: " .. tostring(err))
local game = preview.controller
if not game then os.exit(t.summary() and 0 or 1) end
t.assertEqual(#game.model.levels, 3, "three tracks load and pass their checks")

-- A broken track is a preview error that says what is wrong.
local function renderWith(path, edit)
	local files = projectFiles()
	files["demo/playground/" .. path] = edit(files["demo/playground/" .. path])
	local p = Preview.new(vocabulary, read)
	local ok, problem = p:render(files)
	p:close()
	return ok, tostring(problem)
end
local OVAL = "catalog/tracks/oval.lua"
local ok, problem = renderWith(OVAL, function(s) return s:gsub('"long", "wideRight",\n', '"long", "wideLeft",\n', 1) end)
t.expect(not ok and problem:find("does not join up") and problem:find("facing"), "a track that does not close says where it ends: " .. problem)
ok, problem = renderWith(OVAL, function(s) return s:gsub('"start", "long", "long", "wideRight"', '"start", "long", "long", "right", "right", "wideRight"', 1) end)
t.expect(not ok and problem:find("runs over") or problem:find("does not join up"), "a track over itself is refused")
ok, problem = renderWith(OVAL, function(s) return s:gsub('"long", "wideRight",\n\t\t"long"', '"lnog", "wideRight",\n\t\t"long"', 1) end)
t.expect(not ok and problem:find("'lnog'") and problem:find("wideRight"), "a misspelt piece is named, with the names to use")
ok, problem = renderWith(OVAL, function(s) return s:gsub('{"treeLarge", %-2.6, 3.1', '{"treeLarge", -0.5, 3.1', 1) end)
t.expect(not ok and problem:find("scenery 5") and problem:find("on the road"), "scenery on the road is named")
ok, problem = renderWith(OVAL, function(s) return s:gsub('"tentLong"', '"tentLonger"', 1) end)
t.expect(not ok and problem:find("tentLonger") and problem:find("manifest"), "a misspelt model is named")
ok, problem = renderWith(OVAL, function(s) return s:gsub("pace = 0.7}", "pace = 1.3}", 1) end)
t.expect(not ok and problem:find("pace"), "a rival faster than the player is refused")

-- The race, headless through its SceneView.
local view = game.stage.view
local function frames(n) for _ = 1, n do bridge._sceneSend(view, "frame", 1 / 60) end end
local nodes = bridge._sceneNodes(view)
t.expect(nodes.player and nodes["rival-1"] and nodes["rival-2"], "the player's car and the rivals are on the grid")
t.assertEqual(game.hud.template ~= nil, true, "the HUD renders")

local world = game.model.world
local car = world.player
local startX, startZ = car.x, car.z
bridge._sceneSend(view, "key", "up", true)
frames(60)
t.expect(car.x == startX and car.z == startZ and not world.started, "nobody moves during the countdown")
frames(180)
t.expect(world.started and car.z > startZ + 1, "after Go, Up drives forward")
t.expect(world.rivals[1].s > 6.5, "and the rivals set off")
bridge._sceneSend(view, "key", "right", true)
local yaw = car.yaw
frames(20)
bridge._sceneSend(view, "key", "right", false)
t.expect(((yaw - car.yaw) % 360) > 5 and ((yaw - car.yaw) % 360) < 90, "Right steers right (the heading falls)")
bridge._sceneSend(view, "key", "up", false)

-- Out on the grass the car is held back.
car.x, car.z, car.speed, car.yaw = 8, 3, 15, 0
bridge._sceneSend(view, "key", "up", true)
frames(90)
bridge._sceneSend(view, "key", "up", false)
t.expect(car.offRoad and car.speed <= world.rules.grassSpeed + 1e-6, "the grass slows the car")

-- An autopilot: aim at the road a little ahead, on the side away from a
-- rival close in front (rivals hold their lanes), brake for corners it
-- cannot take, else drive flat out.
-- The template's own modules, for the autopilot and the lap rule.
local Track = assert(load(read(ROOT .. "models/Track.lua"), "@Track.lua"))()
local function autopilot(w)
	return {
		axis = function()
			local p, path = w.player, w.path
			local index = Track.nearest(path, p.x, p.z)
			local s = path.points[index].s
			local lane = 0
			for _, rival in ipairs(w.rivals) do
				local gap = (rival.s - s) % path.length
				if gap < 8 then lane = rival.lane > 0 and -1.3 or 1.3 end
			end
			local tx, tz = Track.at(path, s + 5, lane)
			local want = math.deg(math.atan(tx - p.x, tz - p.z))
			local turn = (want - p.yaw + 180) % 360 - 180
			local steer = math.max(-1, math.min(1, -turn / 15))
			local slowest = w.rules.topSpeed
			for _, ahead in ipairs({0, 3, 6, 9}) do
				local _, _, _, i = Track.at(path, s + ahead, 0)
				slowest = math.min(slowest, math.rad(w.rules.steerRate) * path.points[i].radius * 1.1)
			end
			return steer, p.speed > slowest + 0.5 and 1 or -1
		end,
		held = function() return false end,
		take = function() return false end,
	}
end

for race = 1, 3 do
	game.model:load(race)
	world = game.model.world
	local pilot, seconds = autopilot(world), 0
	local closest = math.huge
	while game.model.state == "playing" and seconds < 240 do
		game.model:step(1 / 30, pilot)
		seconds = seconds + 1 / 30
		for i, a in ipairs(world.rivals) do
			for j = i + 1, #world.rivals do
				local b = world.rivals[j]
				closest = math.min(closest, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
			end
		end
	end
	local name = game.model:level().id
	t.expect(closest >= world.rules.carRadius * 2, string.format("%s: rivals never drive through each other (closest %.2f)", name, closest))
	t.expect(game.model.state == "cleared" or game.model.state == "won", name .. ": the autopilot finishes the race (" .. game.model.state .. ")")
	t.assertEqual(world.player.lap, world.level.laps, name .. ": after every lap")
	t.assertEqual(world.player.place, 1, name .. ": a clean drive wins")
	t.expect(world.player.bestLap and world.player.bestLap > 5, name .. ": a lap takes time: " .. tostring(world.player.bestLap))
	-- The rivals race: none is lapped.
	for _, rival in ipairs(world.rivals) do
		t.expect(rival.s > (world.level.laps - 1) * world.path.length, name .. ": " .. rival.id .. " is on its last lap")
	end
end
t.assertEqual(game.model.state, "won", "winning the last race wins the championship")
game:render()
t.expect(game.model:status().message.title == "Champion!", "the HUD says so")

-- A short cut across the grass does not count as a lap.
game.model:load(1)
world = game.model.world
frames(200)
car = world.player
local Race = assert(load(read(ROOT .. "models/systems/Race.lua"), "@Race.lua"))()
car.x, car.z = Track.at(world.path, world.path.length - 2, 0)
frames(1)
car.x, car.z = Track.at(world.path, 3, 0)
frames(1)
t.assertEqual(car.lap, 0, "jumping from just behind the line to past it skips the quarters: no lap")
t.expect(Race.distance(world, car) < world.path.length, "and the race distance stays on the first lap")

-- Finishing outside the top three races the same track again.
car.lap, car.checkpoint = world.level.laps - 1, 3
for _, rival in ipairs(world.rivals) do rival.s = world.level.laps * world.path.length + 1 end
game.model.rules = {lives = 1, podium = 1}
car.x, car.z = Track.at(world.path, world.path.length - 1, 0)
frames(1)
car.x, car.z = Track.at(world.path, 1, 0)
frames(1)
t.assertEqual(game.model.state, "over", "a finish off the podium is a race to run again")
t.expect(game.model:status().message.title:find("3rd"), "the message names the place")
bridge._sceneSend(view, "key", "return", true)
t.expect(game.model.levelIndex == 1 and game.model.state == "playing", "Return races the same track again")

preview:close()
os.exit(t.summary() and 0 or 1)
