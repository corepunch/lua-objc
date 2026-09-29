_G.__headless = true

-- Coin Quest: every layer on its own (level parsing, each world system with
-- a hand-built map, the session's state machine, input, view data) and
-- then the whole game driven through its SceneView without a window.

local t = require("TestKit")
local bridge = require("AppKitNative")
local Level = require("apps.coin-quest.models.Level")
local World = require("apps.coin-quest.models.World")
local Model = require("apps.coin-quest.Model")
local Levels = require("apps.coin-quest.catalog.Levels")
local InputController = require("apps.coin-quest.controllers.InputController")
local StageController = require("apps.coin-quest.controllers.StageController")
local HudController = require("apps.coin-quest.controllers.HudController")
local Controller = require("apps.coin-quest.Controller")

local function near(a, b) return math.abs(a - b) < 1e-6 end

-- Scripted input: yields the given directions once each, then nothing.
local function script(...)
	local queue = {...}
	return {nextDirection = function() return table.remove(queue, 1) end}
end
local LEFT, RIGHT, UP, DOWN = {x = -1, z = 0}, {x = 1, z = 0}, {x = 0, z = -1}, {x = 0, z = 1}

-- Runs the world until the player stands still.
local function settle(world, input)
	local events = {}
	for _ = 1, 200 do
		for _, event in ipairs(world:step(1 / 60, input)) do table.insert(events, event.name) end
		if not world.player.hop then break end
	end
	return events
end

-- ── Level ──────────────────────────────────────────────────────────────
local level = Level.parse({id = "t", title = "Test", map = {
	"@.$T",
	".  F",
	"*^H$",
}})
t.assertEqual(level.width, 4, "width is the longest row")
t.assertEqual(level.depth, 3, "depth is the number of rows")
t.assertEqual(#level.tiles, 10, "every non-space character is a ground tile")
t.expect(level:walkable(0, 0) and level:walkable(0, 2), "ground and ground cover are walkable")
t.expect(not level:walkable(3, 0), "solid scenery blocks movement")
t.expect(not level:walkable(1, 1), "gaps block movement")
t.expect(not level:walkable(-1, 0) and not level:walkable(9, 9), "outside the map blocks movement")
t.assertEqual(#level.spawns.coins, 2, "coins spawn from $")
t.assertEqual(level.spawns.saws[1].axis, "x", "H saws run along their row")
t.assertEqual(#level.spawns.spikes, 1, "spikes spawn from ^")
t.assertEqual(#level.scenery, 2, "scenery lists solid and decorative props")
for _, bad in ipairs({
	{map = {}, message = "empty"},
	{map = {"@.$?F"}, message = "unknown map character"},
	{map = {".$F"}, message = "no player start"},
	{map = {"@$."}, message = "no flag"},
	{map = {"@..F"}, message = "no coins"},
	{map = {"@@$F"}, message = "more than one player"},
}) do
	local ok, err = pcall(Level.parse, {id = "bad", map = bad.map})
	t.expect(not ok and tostring(err):find(bad.message, 1, true), "a malformed map fails: " .. bad.message)
end

-- Every authored level parses, and every coin and the flag can be reached.
for _, def in ipairs(Levels) do
	local parsed = Level.parse(def)
	local seen, queue = {[parsed.spawns.player.x .. ":" .. parsed.spawns.player.z] = true}, {parsed.spawns.player}
	while #queue > 0 do
		local cell = table.remove(queue)
		for _, d in ipairs({LEFT, RIGHT, UP, DOWN}) do
			local x, z = cell.x + d.x, cell.z + d.z
			if parsed:walkable(x, z) and not seen[x .. ":" .. z] then
				seen[x .. ":" .. z] = true
				table.insert(queue, {x = x, z = z})
			end
		end
	end
	local reachable = true
	for _, coin in ipairs(parsed.spawns.coins) do reachable = reachable and seen[coin.x .. ":" .. coin.z] end
	reachable = reachable and seen[parsed.spawns.flag.x .. ":" .. parsed.spawns.flag.z]
	t.expect(reachable, def.id .. ": every coin and the flag are reachable")
end

-- ── Movement ───────────────────────────────────────────────────────────
local calm = Level.parse({id = "calm", map = {"@.$", "..F", "$.."}})
local world = World.new(calm)
world:step(1 / 60, script(RIGHT))
t.expect(world.player.hop ~= nil, "a direction starts a hop")
t.assertEqual(world.player.x, 1, "the hop's destination is the next cell")
world:step(1 / 60)
local x, y = world:playerPosition()
t.expect(x > 0 and x < 1 and y > 0, "mid-hop the player is between cells and in the air")
t.expect(near(world.player.yaw, 90), "the player faces the way it hops")
settle(world)
x, y = world:playerPosition()
t.expect(near(x, 1) and near(y, 0), "a hop lands on its cell")
world:step(1 / 60, script(UP))
t.expect(world.player.hop == nil and world.player.z == 0, "the edge of the map blocks a hop")
t.expect(near(world.player.yaw, 180), "a blocked hop still turns the player")
world:step(1 / 60, script(DOWN))
local ignored = script(RIGHT)
world:step(1 / 60, ignored)
t.expect(ignored.nextDirection() ~= nil, "input is not read mid-hop")

-- ── Pickups and the flag ───────────────────────────────────────────────
world = World.new(calm)
local events = settle(world, script(RIGHT))
events = settle(world, script(RIGHT))
t.expect(events[1] == "coin" and world:coinsLeft() == 1, "landing on a coin takes it")
t.expect(not world.flag.raised, "the flag waits for every coin")
settle(world, script(LEFT)); settle(world, script(LEFT)); settle(world, script(DOWN))
events = settle(world, script(DOWN))
t.expect(events[1] == "coin" and events[2] == "flagRaised", "the last coin raises the flag")
settle(world, script(RIGHT))
events = settle(world, script(RIGHT))
t.expect(#events == 0, "the flag is not on this cell")
events = settle(world, script(UP))
t.assertEqual(events[1], "cleared", "landing on the raised flag clears the level")

-- ── Saws ───────────────────────────────────────────────────────────────
local mill = Level.parse({id = "mill", map = {"@....", "H..$F"}})
world = World.new(mill)
local turned = false
for _ = 1, 240 do
	world:step(1 / 60)
	t.expect(world.saws[1].x >= -0.01 and world.saws[1].x <= 4.01, "a saw never leaves the ground")
	if world.saws[1].direction < 0 then turned = true end
end
t.expect(turned, "a saw turns around at the end of the ground")
world = World.new(mill)
world.saws[1].x, world.saws[1].z = 0, 0
events = world:step(1 / 60)
t.assertEqual(events[1] and events[1].name, "hurt", "a saw touching the player hurts it")
events = world:step(1 / 60)
t.expect(#events == 0, "a recovering player cannot be hurt again")

-- ── Spikes ─────────────────────────────────────────────────────────────
local spiky = Level.parse({id = "spiky", map = {"@^$F"}})
world = World.new(spiky)
world.rules = setmetatable({spikeStagger = 0}, {__index = World.RULES})
world:step(0.01)
t.expect(world.spikes[1].raised, "spikes start the cycle raised")
world.time = World.RULES.spikeRaised + 0.1
world:step(0.01)
t.expect(not world.spikes[1].raised, "spikes sink for the rest of the cycle")
for _ = 1, 30 do world:step(1 / 60) end
t.expect(near(world.spikes[1].lift, 0), "sunk spikes ease all the way down")
t.expect(#settle(world, script(RIGHT)) == 0, "standing on sunk spikes is safe")
world.time = World.RULES.spikeCycle - 0.02
local hurt = false
for _ = 1, 5 do
	for _, event in ipairs(world:step(1 / 60)) do hurt = hurt or event.name == "hurt" end
end
t.expect(hurt, "spikes rising under a standing player hurt it")
local pose
for _, p in ipairs(world:poses()) do if p.id == "spikes-1" then pose = p end end
t.expect(pose and pose.y ~= nil, "spikes are posed by their lift")

-- ── Session ────────────────────────────────────────────────────────────
local catalog = {
	{id = "one", title = "One", map = {"@$F"}},
	{id = "two", title = "Two", map = {"@$F"}},
}
local session = Model.new(catalog)
t.assertEqual(session.state, "playing", "a session starts playing")
t.assertEqual(session:status().stage, "Level 1 of 2", "status names the level position")
local revision = session.revision
session:step(1 / 60, script(RIGHT))
t.assertEqual(session.revision, revision, "a hop alone changes nothing but poses")
for _ = 1, 30 do session:step(1 / 60) end
t.expect(session.score == 1 and session.revision > revision, "a coin scores and bumps the revision")
t.expect(session.world.flag.raised, "the flag rises in the session's world")
session:step(1 / 60, script(RIGHT))
for _ = 1, 30 do session:step(1 / 60) end
t.assertEqual(session.state, "cleared", "reaching the flag clears the level")
t.assertEqual(session:status().message.title, "Level Complete", "the HUD message follows the state")
local x0 = session.world.player.x
session:step(1 / 60, script(LEFT))
t.assertEqual(session.world.player.x, x0, "nothing moves once the level ends")
session:advance()
t.expect(session.levelIndex == 2 and session.state == "playing", "advance loads the next level")
t.assertEqual(session.score, 1, "the score carries to the next level")
session:step(1 / 60, script(RIGHT)); for _ = 1, 30 do session:step(1 / 60) end
session:step(1 / 60, script(RIGHT)); for _ = 1, 30 do session:step(1 / 60) end
t.assertEqual(session.state, "won", "clearing the last level wins")
session:advance()
t.expect(session.levelIndex == 1 and session.score == 0 and session.lives == 3, "advance after winning restarts")

session = Model.new({{id = "saw", title = "Saw", map = {"@...", "H..$F"}}})
session.world.saws[1].x, session.world.saws[1].z = 0, 0
session:step(1 / 60)
t.expect(session.lives == 2 and session.state == "playing", "a hit costs a life")
session.world.player.recovering = 0
local player = session.world.player
player.x, player.fromX = 3, 3
session.world.saws[1].x, session.world.saws[1].z = 3, 0
session:step(1 / 60)
t.expect(session.world.player.x == 0, "a hit player respawns at the start")
session.lives = 1
session.world.player.recovering = 0
session.world.saws[1].x, session.world.saws[1].z = 0, 0
session:step(1 / 60)
t.expect(session.lives == 0 and session.state == "over", "the last life ends the game")
t.assertEqual(session:status().message.title, "Game Over", "game over shows its message")

-- ── Input ──────────────────────────────────────────────────────────────
local commands = {}
local input = InputController.new({advance = function() table.insert(commands, "advance") end,
	restart = function() table.insert(commands, "restart") end})
t.expect(input:key("left", true), "arrow keys are handled")
t.expect(input:key("left", false), "releases are handled")
t.expect(input:nextDirection().x == -1, "a tap released before it was read still counts")
t.expect(input:nextDirection() == nil, "a tap counts once")
input:key("w", true)
t.expect(input:nextDirection().z == -1 and input:nextDirection().z == -1, "a held key keeps hopping")
input:key("d", true)
t.expect(input:nextDirection().x == 1, "the latest held direction wins")
input:key("d", false)
t.expect(input:nextDirection().z == -1, "releasing it falls back to the earlier held key")
input:key("w", false)
t.expect(input:nextDirection() == nil, "nothing held, nothing read")
t.expect(input:key("return", true) and input:key("r", true), "command keys are handled")
t.expect(commands[1] == "advance" and commands[2] == "restart", "command keys run their commands")
t.expect(not input:key("q", true), "other keys are left to the system")
input:key("s", true); input:reset()
t.expect(input:nextDirection().z == 1, "reset forgets taps but keeps held keys")

-- ── View data ──────────────────────────────────────────────────────────
local scene = Model.new(Levels):scene()
local data = StageController.viewData(scene)
t.assertEqual(#data.tiles, #scene.tiles, "every tile is drawn")
t.expect(data.coins[1] ~= scene.coins[1], "templates receive copies, never live entities")
t.expect(data.flag == nil, "the flag is not drawn until it rises")
local camera = StageController.camera(11, 7)
local cx, cy, cz = camera.position:match("(%S+) (%S+) (%S+)")
t.expect(near(tonumber(cx), 5) and tonumber(cy) > 0 and tonumber(cz) > 3, "the camera looks down on the level from the front")
local wide = StageController.camera(21, 7)
t.expect(tonumber(wide.position:match("%S+ (%S+)")) > tonumber(cy), "a wider level pulls the camera back")
local hud = HudController.viewData({level = "L", stage = "Level 1 of 3", coins = 2, totalCoins = 5, score = 2,
	lives = 1, maxLives = 3, state = "playing"})
t.assertEqual(hud.coins, "2 / 5", "the HUD counts coins taken")
t.expect(hud.hearts[1].filled and not hud.hearts[2].filled, "hearts show lives left")
t.expect(hud.message == nil, "no message while playing")

-- ── The whole game, headless ───────────────────────────────────────────
local app = Controller.new({levels = {{id = "mini", title = "Mini", map = {"@$F"}}, {id = "next", title = "Next", map = {"$@F"}}}})
app:createWindow()
local view = app.stage.view
local nodes = bridge._sceneNodes(view)
t.expect(nodes.player and nodes["coin-1"] and nodes["level-mini"], "the stage template builds the level")
t.expect(nodes["coin-1"].spinning, "coins spin natively, not from Lua")
t.expect(nodes.flag == nil, "the flag is absent until every coin is taken")
t.expect(app.hud.refs.level.text == "Mini", "the HUD names the level")
t.expect(bridge._sceneSend(view, "key", "right", true), "the stage forwards keys to input")
bridge._sceneSend(view, "key", "right", false)
for _ = 1, 20 do bridge._sceneSend(view, "frame", 1 / 60) end
nodes = bridge._sceneNodes(view)
t.expect(near(nodes.player.x, 1), "frames step the game and pose the player")
t.expect(nodes["coin-1"] == nil, "a taken coin leaves the scene")
t.expect(nodes.flag ~= nil, "the flag rises into the scene")
t.assertEqual(app.hud.refs.coins.text, "1 / 1", "the HUD counts the coin")
bridge._sceneSend(view, "key", "right", true)
bridge._sceneSend(view, "key", "right", false)
for _ = 1, 20 do bridge._sceneSend(view, "frame", 1 / 60) end
t.assertEqual(app.model.state, "cleared", "reaching the flag clears the level")
t.assertEqual(app.hud.refs.messageTitle.text, "Level Complete", "the HUD announces it")
bridge._sceneSend(view, "key", "return", true)
nodes = bridge._sceneNodes(view)
t.expect(nodes["level-next"] and not nodes["level-mini"], "Return swaps in the next level's subtree")
t.expect(rawequal(view, app.stage.view), "levels reuse the same SceneView")
t.expect(near(nodes.player.x, 1), "the player stands on the new start")
t.expect(app.hud.refs.messageTitle == nil, "the message leaves once play resumes")
local frameBefore = app.model.world.time
app:tick(5)
t.expect(near(app.model.world.time - frameBefore, 0.1), "a stalled frame is capped")

os.exit(t.summary() and 0 or 1)
