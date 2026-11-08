_G.__headless = true

-- lua/game on its own, with a hand-built one-system world: the session's
-- state machine and revision, unknown events, World.extend and systems
-- order, Input bindings (custom buttons, held, pad, taps, reset), the leash
-- camera, and Stage's plain records and camera pose.

local t = require("TestKit")
local Session = require("game.Session")
local World = require("game.World")
local Input = require("game.Input")
local Leash = require("game.cameras.Leash")
local Chase = require("game.cameras.Chase")
local Stage = require("game.Stage")

-- ── World ────────────────────────────────────────────────────────────────
local order = {}
local Collect = {update = function(world, _, input)
	table.insert(order, "collect")
	for _, gem in ipairs(world.gems) do
		if not gem.taken and input and input:take("grab") then gem.taken = true; world:emit("gem", gem) end
	end
	if #World.left(world.gems) == 0 and not world.done then world.done = true; world:emit("cleared") end
end}
local Danger = {update = function(world)
	table.insert(order, "danger")
	if world.level.deadly and world.time > 0.5 and not world.hit then world.hit = true; world:emit("hurt") end
end}
local GemWorld = World:extend({RULES = {speed = 2}, SYSTEMS = {Collect, Danger}})
function GemWorld.new(level, rules)
	local self = World.create(level, rules, GemWorld)
	self.gems = World.spawnAll(level.gems, "gem", function(gem) gem.shine = true end)
	return self
end
function GemWorld:respawn() self.respawned = (self.respawned or 0) + 1 end
function GemWorld:poses() return {} end

local world = GemWorld.new({gems = {{x = 1}, {x = 2}}})
t.assertEqual(world.gems[2].id, "gem-2", "spawned entities are numbered by kind")
t.expect(world.gems[1].shine and world.gems[1].x == 1, "spawns keep their fields and gain per-kind state")
t.assertEqual(world.rules.speed, 2, "a world takes its class's rules")
world:step(0.1, nil)
t.assertEqual(table.concat(order, ","), "collect,danger", "systems run in SYSTEMS order")

-- ── Session ──────────────────────────────────────────────────────────────
local Game = Session:extend({
	World = GemWorld,
	parse = function(def) return def end,
	RULES = {lives = 2},
	REACTIONS = {gem = function(self) self.score = self.score + 1 end},
	QUIET = {},
})
local grabs = 0
local pad = {take = function(_, button) if button == "grab" and grabs > 0 then grabs = grabs - 1; return true end return false end}
local session = Game.new({{gems = {{x = 1}}}, {gems = {{x = 1}, {x = 2}}, deadly = true}})
t.expect(session.state == "playing" and session.levelIndex == 1 and session.lives == 2, "a session starts on level 1 with full lives")
local revision = session.revision
session:step(1 / 60, pad)
t.assertEqual(session.revision, revision, "a step with no events renders nothing")
grabs = 1
session:step(1 / 60, pad)
t.expect(session.score == 1 and session.state == "cleared", "a reaction scores, and the default `cleared` ends the level")
t.expect(session.revision > revision, "visible changes move the revision")
session:advance()
t.expect(session.levelIndex == 2 and session.state == "playing", "advance loads the next level")
for _ = 1, 40 do session:step(1 / 60, pad) end
t.expect(session.lives == 1 and session.world.respawned == 1, "the default `hurt` costs a life and respawns")
session.lives = 1
session.world.hit = false
for _ = 1, 40 do session:step(1 / 60, pad) end
t.assertEqual(session.state, "over", "the last life ends the game")
session:advance()
t.expect(session.levelIndex == 2 and session.lives == 2 and session.score == 1, "over restarts the level with the score it began with")
grabs = 2
session:step(1 / 60, pad)
session:step(1 / 60, pad)
t.assertEqual(session.state, "won", "clearing the last level wins")
session:advance()
t.expect(session.levelIndex == 1 and session.score == 0, "advance after winning starts again")

local Typo = Session:extend({World = GemWorld, parse = function(d) return d end, REACTIONS = {}})
local typo = Typo.new({{gems = {{x = 1}}}})
grabs = 1
local ok, err = pcall(function() typo:step(1 / 60, pad) end)
t.expect(not ok and tostring(err):find("'gem'"), "an event without a reaction is an error naming it")
t.assertThrows(function() Game.new({}) end, "a session needs a level")

-- ── Input ────────────────────────────────────────────────────────────────
local commands = {}
local input = Input.new({advance = function() table.insert(commands, "advance") end},
	{buttons = {space = "fire", f = "grab"}, pad = {a = "fire"}, tap = "fire"})
t.expect(input:key("space", true) and input:held("fire") and input:take("fire"), "a bound key presses and holds its button")
t.expect(not input:take("fire") and input:held("fire"), "a press is taken once; the key stays held")
input:key("space", false)
t.expect(not input:held("fire"), "letting go releases it")
t.expect(not input:take("jump"), "unbound buttons are never pressed")
local x, z = input:axis()
t.expect(x == 0 and z == 0, "buttons are not directions")
input:key("d", true); x = input:axis(); input:key("d", false)
t.assertEqual(x, 1, "default directions stay bound")
input:gamepad({a = true})
t.expect(input:take("fire") and input:held("fire"), "a controller button presses and holds its button")
input:gamepad({a = true})
t.expect(not input:take("fire"), "a held controller button presses once")
input:gamepad(nil)
input:press()
t.expect(input:take("fire"), "a tap presses the tap button")
input:press("grab"); input:reset()
t.expect(not input:take("grab"), "reset forgets presses")
t.expect(input:key("return", true) and commands[1] == "advance", "command keys run commands")

-- ── Leash camera ─────────────────────────────────────────────────────────
local cam = {player = {x = 0, y = 0, z = 0}, rules = Leash.RULES, level = {facing = 0}}
Leash.place(cam)
t.expect(math.abs(cam.camera.z - Leash.RULES.cameraFar) < 1e-9 and cam.camera.x == 0, "the camera starts behind, facing the level")
cam.player.z = -20
for _ = 1, 600 do Leash.update(cam, 1 / 60, nil) end
local dz = cam.camera.z - cam.focus.z
t.expect(dz >= Leash.RULES.cameraNear - 1e-6 and dz <= Leash.RULES.cameraFar + 1e-6, "running away pulls the camera along within its leash")
local fx, fz = Leash.forward(cam)
t.expect(math.abs(fx) < 1e-6 and fz < 0, "forward is the camera's view direction")

-- ── Stage ────────────────────────────────────────────────────────────────
local live = {{id = "a", x = 1, secret = {}}}
local cells = Stage.cells(live, {"id", "x"})
t.expect(cells[1].id == "a" and cells[1].secret == nil and cells[1] ~= live[1], "cells copy only the named fields")
local pose = Stage:cameraPose({position = {x = 0, y = 4, z = 6}, focus = {x = 0, y = 1, z = 0}})
t.expect(pose.id == "camera" and pose.lookY == 1 + Stage.CAMERA.lift, "the camera looks a little above its focus")
t.assertEqual(Stage:camera({position = {x = 0, y = 4, z = 6}, focus = {x = 0, y = 1, z = 0}}).position, "0.000 4.000 6.000",
	"camera attributes are template strings")

-- ── Chase camera ─────────────────────────────────────────────────────────
local chase = {player = {x = 0, y = 0, z = 0, yaw = 0}, rules = Chase.RULES}
Chase.place(chase)
t.expect(math.abs(chase.camera.z + Chase.RULES.chaseDistance) < 1e-9 and math.abs(chase.camera.x) < 1e-9,
	"the chase camera starts behind the heading (yaw 0 drives toward +z)")
t.expect(math.abs(chase.focus.z - Chase.RULES.chaseAhead) < 1e-9, "and looks ahead of the car")
t.assertEqual(Chase.turn(350, 10), 20, "the camera turns the short way round")
chase.player.yaw = 90
Chase.update(chase, 1 / 60)
t.expect(chase.chaseYaw > 0 and chase.chaseYaw < 10, "a turn of the car swings the camera round after it")
for _ = 1, 600 do Chase.update(chase, 1 / 60) end
t.expect(math.abs(chase.chaseYaw - 90) < 0.01 and math.abs(chase.camera.x + Chase.RULES.chaseDistance) < 0.01,
	"and settles behind the new heading")
chase.player.x = 100
Chase.update(chase, 1 / 60)
t.expect(math.abs(chase.camera.x - (100 - Chase.RULES.chaseDistance)) < 0.01, "the camera keeps its distance at any speed")

os.exit(t.summary() and 0 or 1)
