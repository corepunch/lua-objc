_G.__headless = true

-- Lua Studio's Platformer template (apps/studio/Documents/Games/Platformer),
-- run the way Studio runs a project: through its Preview sandbox, which
-- allows only framework modules, the shared game layer and kit manifests.
-- Every level loads and passes its reachability check; a broken level is a
-- preview error naming the problem; then the game plays headlessly: the
-- hero stands, runs, jumps, plays its clips and takes a coin.

local t = require("TestKit")
local bridge = require("AppKitNative")
local AppKit = require("AppKit")
local Preview = require("apps.studio.services.Preview")

local ROOT = "apps/studio/Documents/Games/Platformer/"
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

-- Studio's template list names the template, and every listed file exists.
local templates = assert(load(read("apps/studio/Documents/templates.lua"), "@templates.lua", "t", {}))()
local listed = false
for _, entry in ipairs(templates) do if entry.id == "Platformer" and entry.path == "Games/Platformer" then listed = true end end
t.expect(listed, "the New Project sheet offers the Platformer template")

-- Studio hosts the window's content in a hosting controller; headless, the
-- content itself stands in.
local vocabulary = {}
for k, v in pairs(AppKit) do vocabulary[k] = v end
vocabulary.HostingController = function(content) return content end
local preview = Preview.new(vocabulary, read)

local content, err = preview:render(projectFiles())
t.expect(content ~= nil, "the template renders in Studio's preview: " .. tostring(err))
local game = preview.controller
if not game then os.exit(t.summary() and 0 or 1) end
t.assertEqual(#game.model.levels, 3, "three levels load and pass their checks")

-- A broken level is a preview error that says what is wrong.
local function renderWith(path, edit)
	local files = projectFiles()
	files["demo/playground/" .. path] = edit(files["demo/playground/" .. path])
	local p = Preview.new(vocabulary, read)
	local ok, problem = p:render(files)
	p:close()
	return ok, tostring(problem)
end
local ok, problem = renderWith("catalog/levels/meadow.lua", function(s) return s:gsub("{0.6, 1, %-2.7}", "{0.6, 9, -2.7}", 1) end)
t.expect(not ok and problem:find("coin 2") and problem:find("cannot be reached"), "an unreachable coin is named")
ok, problem = renderWith("catalog/levels/meadow.lua", function(s) return s:gsub('"block%-grass%-large", 0, 0, 0', '"block-grass-larg", 0, 0, 0', 1) end)
t.expect(not ok and problem:find("block%-grass%-larg") and problem:find("manifest"), "a misspelt model is named")
ok, problem = renderWith("catalog/levels/meadow.lua", function(s) return s:gsub("start = {0, 1, 0.3}", "start = {0, 5, 0.3}", 1) end)
t.expect(not ok and problem:find("start"), "a start in mid-air is refused")
ok, problem = renderWith("catalog/levels/hills.lua", function(s) return s:gsub("springs = {%s*{0.6, 2, %-3.3},%s*},", "", 1) end)
t.expect(not ok and problem:find("hills") and problem:find("reached"), "removing the spring makes the tower's coin unreachable")

-- The game, headless through its SceneView.
local view = game.stage.view
local world = game.model.world
local function frames(n) for _ = 1, n do bridge._sceneSend(view, "frame", 1 / 60) end end
local nodes = bridge._sceneNodes(view)
t.expect(nodes.player and nodes.player.skinned, "the hero is the kit's skinned character")
t.assertEqual(nodes.player.animation, "idle", "the hero idles at the start")
t.expect(nodes["coin-1"] ~= nil and nodes.flag == nil, "coins are out and the flag waits for them")

local startY = world.player.y
frames(120)
t.expect(math.abs(world.player.y - startY) < 1e-6 and world.player.grounded, "the hero stands on the start island")

bridge._sceneSend(view, "key", "up", true)
frames(10)
t.expect(world.player.z < 0.3 - 0.5, "up runs away from the camera")
t.assertEqual(bridge._sceneNodes(view).player.animation, "walk", "running plays the walk clip")
bridge._sceneSend(view, "key", "up", false)
frames(30)

bridge._sceneSend(view, "key", "space", true)
bridge._sceneSend(view, "key", "space", false)
local top = world.player.y
for _ = 1, 60 do frames(1); top = math.max(top, world.player.y) end
t.expect(top - startY > 1.3 and top - startY < 1.7, "a jump rises about one and a half units")
t.assertEqual(world.player.grounded, true, "and lands")

-- Walk the hero onto the second coin's island and take it.
local coin = world.coins[2]
world.player.x, world.player.y, world.player.z = coin.x, coin.y, coin.z + 0.2
local score = game.model.score
frames(2)
t.expect(coin.taken and game.model.score == score + 1, "touching a coin takes it")
t.expect(bridge._sceneNodes(view)["coin-2"] == nil, "a taken coin leaves the scene")

-- Every coin taken raises the flag; touching it clears the level.
for _, c in ipairs(world.coins) do c.taken = true end
frames(1)
t.expect(world.flag.raised and bridge._sceneNodes(view).flag ~= nil, "the flag rises after the last coin")
world.player.x, world.player.y, world.player.z = world.flag.x, world.flag.y, world.flag.z
frames(1)
t.assertEqual(game.model.state, "cleared", "touching the flag clears the level")
bridge._sceneSend(view, "key", "return", true)
t.expect(game.model.levelIndex == 2 and game.model.state == "playing", "Return starts the next level")

-- Falling into the sea costs a life and puts the hero back at the start.
world = game.model.world
world.player.y = -10
frames(1)
t.expect(game.model.lives == 2 and math.abs(world.player.y - world.level.start.y) < 1e-6, "a fall costs a life and respawns")

preview:close()
os.exit(t.summary() and 0 or 1)
