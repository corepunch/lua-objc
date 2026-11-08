_G.__headless = true

-- glTF models (src/shared/scene_gltf.m) in a SceneView: Kenney's binary
-- .glb files and a hand-made JSON .gltf load with their true bounds; a
-- skinned character clones with bones of its own; a model's clips play by
-- name through `animation`; broken files are reported, not drawn.

local t = require("TestKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")

local KIT = "assets/kenney/platformer-kit/models/"
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1e-3) end

local function scene(body, data)
	local _, refs = xml.render('<SceneView id="stage">' .. body .. '</SceneView>', data or {})
	return refs.stage, bridge._sceneNodes(refs.stage)
end

-- Static models keep the kit's dimensions: the coin is 0.4 wide and tall and
-- stands on its origin, as its OBJ twin did.
local _, nodes = scene('<Node id="coin" model="' .. KIT .. 'coin-gold.glb" />'
	.. '<Node id="block" model="' .. KIT .. 'block-grass.glb" position="3 0 0" />'
	.. '<Node id="spring" model="' .. KIT .. 'spring.glb" />')
t.expect(near(nodes.coin.width, 0.4) and near(nodes.coin.height, 0.4) and near(nodes.coin.length, 0.175),
	"a GLB coin keeps its 0.4 x 0.4 x 0.175 bounds")
t.expect(near(nodes.coin.bottom, 0), "a GLB model stands on its origin")
t.expect(near(nodes.block.height, 1) and near(nodes.block.width, 1.0821, 1e-3), "a block is one unit tall")
t.expect(nodes.spring.height > 0.3, "child nodes keep their translation (the spring's platform sits on top)")
t.expect(nodes.coin.skinned == false and #nodes.coin.clips == 0, "a static model has no skin and no clips")

-- A skinned character: its bind pose matches the static OBJ export, every
-- clone deforms with bones inside itself, and its clips are named.
local stage
stage, nodes = scene('<Node id="a" model="' .. KIT .. 'character-oobi.glb" />'
	.. '<Node id="b" model="' .. KIT .. 'character-oobi.glb" position="2 0 0" animation="walk" />')
t.expect(nodes.a.skinned and nodes.a.ownBones and nodes.b.ownBones, "each clone of a skinned model has its own bones")
t.expect(near(nodes.a.height, 0.9074, 1e-3), "the character's bind pose is its rest shape")
local clips = table.concat(nodes.a.clips, " ")
t.expect(clips:find("idle") and clips:find("walk") and clips:find("jump"), "the character's clips load by name")
t.expect(nodes.a.animation == nil, "no clip plays unless one is asked for")
t.assertEqual(nodes.b.animation, "walk", "animation= plays a clip")

-- Changing `animation` switches clips on the same clone; removing it stops.
local function graph(animation)
	return bridge._sceneGraph(stage, {
		{sceneKind = "node", id = "b", model = KIT .. "character-oobi.glb", position = "2 0 0", animation = animation},
	})
end
t.assertEqual(#graph("idle"), 0, "a known clip is no problem")
t.assertEqual(bridge._sceneNodes(stage).b.animation, "idle", "a new clip replaces the old one")
graph(nil)
t.expect(bridge._sceneNodes(stage).b.animation == nil, "no animation stops the clip")
local problems = graph("moonwalk")
t.expect(#problems == 1 and problems[1]:find("moonwalk"), "an unknown clip is reported by name")

-- A JSON glTF with an external buffer, scale, an unlit material and a clip.
_, nodes = scene('<Node id="tri" model="tests/fixtures/gltf/triangle.gltf" animation="rise" />')
t.expect(near(nodes.tri.width, 2) and near(nodes.tri.height, 2), "a node's scale applies (a unit triangle at 2x)")
t.assertEqual(nodes.tri.animation, "rise", "a clip from a JSON glTF plays")

-- Broken files are problems, never a crash.
local ok, err = pcall(xml.render, '<SceneView><Node id="x" model="tests/fixtures/gltf/broken.glb" /></SceneView>', {})
t.expect(not ok and tostring(err):find("broken.glb"), "an unreadable GLB is reported with its path")
ok, err = pcall(xml.render, '<SceneView><Node id="x" model="no/such/model.glb" /></SceneView>', {})
t.expect(not ok and tostring(err):find("cannot read"), "a missing GLB is reported")

os.exit(t.summary() and 0 or 1)
