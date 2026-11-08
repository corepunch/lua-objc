-- The 3-D stage of a game: renders the game's Stage template into its host
-- when the scene's structure changes, and hands the SceneView fresh poses
-- every frame, the camera's among them.
--
-- A game's stage controller extends it with `viewData(scene)`, which turns
-- the session's scene (plain entity lists) into template data:
--
--   local StageController = require("game.Stage"):extend({VIEW = "apps/mygame/views/Stage.etlua"})
--   function StageController.viewData(scene) return {...} end
--
-- Copy entities into plain view records (Stage.cells) before rendering:
-- `partial()` adds its helpers to the table it receives, and templates must
-- never hold or mutate live game state. The template names its SceneView
-- `id="scene"` and binds onKey, onFrame, onSwipe and onTap to the actions.
local Template = require("ui.template")

local Stage = {}
Stage.__index = Stage

-- A horizontal field of view keeps the same width of world in view however
-- the window is shaped; the lens looks a little above the point it follows.
Stage.CAMERA = {fieldOfView = 70, lift = 0.6}

function Stage:extend(class)
	class = class or {}
	class.__index = class
	setmetatable(class, {__index = self})
	class.new = function(host, ns, actions) return Stage.create(class, host, ns, actions) end
	return class
end

-- `actions` are the SceneView's key, frame, swipe and tap callbacks.
function Stage.create(class, host, ns, actions)
	return setmetatable({template = Template.new(host, class.VIEW, ns), actions = actions}, class)
end

-- Plain records holding only `fields` of each item.
function Stage.cells(list, fields)
	local records = {}
	for _, item in ipairs(list or {}) do
		local record = {}
		for _, field in ipairs(fields) do record[field] = item[field] end
		table.insert(records, record)
	end
	return records
end

function Stage.vector(x, y, z) return string.format("%.3f %.3f %.3f", x, y, z) end

-- The camera's pose for a view `{position, focus}`.
function Stage:cameraPose(view)
	local p, f = view.position, view.focus
	return {id = "camera", x = p.x, y = p.y, z = p.z, lookX = f.x, lookY = f.y + self.CAMERA.lift, lookZ = f.z}
end

-- The <Camera> attributes a template starts from, for the same view.
function Stage:camera(view)
	local p, f = view.position, view.focus
	return {
		position = Stage.vector(p.x, p.y, p.z),
		lookAt = Stage.vector(f.x, f.y + self.CAMERA.lift, f.z),
		fieldOfView = self.CAMERA.fieldOfView,
		fieldOfViewAxis = "horizontal",
	}
end

function Stage:render(scene)
	local data = self.viewData(scene, self)
	data.actions = self.actions
	local _, refs = self.template:update(data)
	self.view = refs.scene
	return self.view
end

-- The state of the game controller playing, if any (the SceneView's
-- `gamepad`).
function Stage:gamepad()
	return self.view and self.view.gamepad
end

-- The frame's poses, and the camera's for `view` ({position, focus}).
function Stage:pose(poses, view)
	if view then table.insert(poses, self:cameraPose(view)) end
	self.view.nodeStates = poses
end

return Stage
