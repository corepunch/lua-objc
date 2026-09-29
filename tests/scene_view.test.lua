_G.__headless = true

-- SceneView: a SceneKit scene graph described by <Node>, <Camera> and
-- <Light> records that reconciles by id, poses from game state, and the
-- keyboard and frame hooks a game loop needs.

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local bridge = require("AppKitNative")

local COIN = "apps/coin-quest/assets/models/coin-gold.obj"

local function near(a, b) return math.abs(a - b) < 1e-4 end

-- Construction from a template.
local keys, frames = {}, {}
local view, refs = xml.render([[
<SceneView id="stage" background="#8fd3f4" onKey="key" onFrame="frame">
	<Camera id="eye" position="0 6 8" lookAt="0 0 0" fieldOfView="40" />
	<Light id="sun" type="directional" rotation="-60 30 0" castsShadow="true" />
	<Light type="ambient" intensity="300" />
	<Node id="ground" geometry="box" width="4" height="1" length="4" color="systemGreen" position="0 -0.5 0" />
	<Node id="coin" model="]] .. COIN .. [[" position="1 0 2" spin="90" bob="0.1" transition="pop" />
	<Node id="group" position="0 1 0" rotation="0 90 0">
		<Node id="child" geometry="sphere" radius="0.25" position="1 0 0" />
	</Node>
</SceneView>]], {
	actions = {
		key = function(_, key, pressed) table.insert(keys, {key, pressed}); return key ~= "q" end,
		frame = function(_, dt) table.insert(frames, dt) end,
	},
})
local stage = refs.stage
t.expect(stage ~= nil, "SceneView renders a native view with its id")
t.expect(stage.fillWidth and stage.fillHeight, "a scene fills its proposal like SwiftUI's SceneView")

local nodes = bridge._sceneNodes(stage)
t.assertEqual(nodes.eye.kind, "camera", "Camera records become camera nodes")
t.expect(nodes.eye.camera, "the first camera is the point of view")
t.assertEqual(nodes.sun.light, "directional", "Light records carry their type")
t.assertEqual(nodes["/3"].light, "ambient", "an unidentified node is keyed by its position")
t.expect(near(nodes.ground.y, -0.5), "position is parsed from x y z")
t.assertEqual(nodes.ground.parts, 1, "primitive geometry is the node's content")
t.expect(nodes.coin.parts >= 1, "a model file loads into the node")
t.expect(nodes.coin.spinning and nodes.coin.bobbing, "idle behaviours run on the content")
t.assertEqual(nodes.child.parent, "group", "child records hang from their parent node")
t.expect(near(nodes.group.yaw, 90), "rotation is in degrees")
t.expect(near(nodes.coin.scale, 1), "the first build plays no insertion transition")

-- Poses from game state move nodes without describing the scene again.
stage.nodeStates = {
	{id = "coin", x = 3, y = 0.5, z = -1, yaw = 45, opacity = 0.5},
	{id = "missing", x = 9},
	{id = "group", scale = 2},
}
nodes = bridge._sceneNodes(stage)
t.expect(near(nodes.coin.x, 3) and near(nodes.coin.y, 0.5) and near(nodes.coin.z, -1), "nodeStates sets positions")
t.expect(near(nodes.coin.yaw, 45), "nodeStates sets yaw in degrees")
t.expect(near(nodes.coin.opacity, 0.5), "nodeStates sets opacity")
t.expect(near(nodes.group.scale, 2), "nodeStates sets a uniform scale")
t.expect(nodes.coin.spinning, "a pose does not cancel idle behaviours")
t.expect(nodes.missing == nil, "an unknown id is ignored")
stage.nodeStates = {{id = "coin", yaw = 90}}
t.expect(near(bridge._sceneNodes(stage).coin.x, 3), "a partial pose keeps the fields it omits")

-- Keyboard and frame hooks.
t.expect(bridge._sceneSend(stage, "key", "left", true), "onKey reports handled presses")
t.expect(not bridge._sceneSend(stage, "key", "q", true), "onKey can decline a key")
t.assertEqual(keys[1][1], "left", "onKey receives the key name")
t.assertEqual(keys[1][2], true, "onKey receives whether it was pressed")
bridge._sceneSend(stage, "frame", 1 / 60)
t.expect(#frames == 1 and near(frames[1], 1 / 60), "onFrame receives the frame interval")

-- Retained reconciliation: nodes match by id and keep their state.
local host = ns.VStack({})
local template = Template.new(host, "tests/fixtures/scene_view/Scene.etlua", ns)
local function render(data)
	local _, sceneRefs = template:update(data)
	return sceneRefs.scene
end
local scene = render({coins = {{id = "a", x = 0}, {id = "b", x = 1}}, cameraY = 5})
nodes = bridge._sceneNodes(scene)
t.expect(nodes.a and nodes.b, "template nodes are built")
scene.nodeStates = {{id = "player", x = 4, z = 2}}
local scene2 = render({coins = {{id = "b", x = 1}}, cameraY = 5})
t.expect(rawequal(scene, scene2), "new records reconcile into the same SceneView")
nodes = bridge._sceneNodes(scene)
t.expect(nodes.a == nil, "a node missing from the template is removed")
t.expect(nodes.b ~= nil, "surviving nodes stay")
t.expect(near(nodes.player.x, 4) and near(nodes.player.z, 2),
	"an unchanged position attribute does not snap a moving node back")
render({coins = {{id = "b", x = 1}, {id = "c", x = 2}}, cameraY = 7})
nodes = bridge._sceneNodes(scene)
t.expect(nodes.c ~= nil, "an inserted node is built")
t.expect(near(nodes.c.scale, 0), "an inserted node starts its pop transition from nothing")
t.expect(near(nodes.cam.y, 7), "a changed attribute applies in place")
render({coins = {{id = "b", x = 5}}, cameraY = 7})
t.expect(near(bridge._sceneNodes(scene).b.x, 5), "a changed position moves the node")

-- Edge cases.
local empty = xml.render('<SceneView id="s" />', {})
t.expect(next(bridge._sceneNodes(empty)) == nil, "an empty scene has no nodes")
local ok, err = pcall(xml.render, '<SceneView><Node id="x" model="missing/file.obj" /></SceneView>', {})
t.expect(not ok and tostring(err):find("x:", 1, true), "an unreadable model names its node")
ok, err = pcall(xml.render, '<SceneView><Node id="x" geometry="teapot" /></SceneView>', {})
t.expect(not ok and tostring(err):find("unknown geometry", 1, true), "an unknown geometry is an error")
ok, err = pcall(xml.render, '<SceneView><Node id="x" /><Node id="x" /></SceneView>', {})
t.expect(not ok and tostring(err):find("duplicate", 1, true), "duplicate ids are an error")
ok = pcall(xml.render, '<SceneView><Label text="no" /></SceneView>', {})
t.expect(not ok, "SceneView accepts only scene records")

os.exit(t.summary() and 0 or 1)
