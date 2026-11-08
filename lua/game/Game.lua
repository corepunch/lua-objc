-- A game's root controller: creates the window, runs the game loop and
-- coordinates input, stage and HUD. A game extends it with its parts:
--
--   return require("game.Game"):extend({
--       WINDOW = "apps/mygame/views/layouts/Window.etlua", -- with #stage and #hud hosts
--       Model = require("apps.mygame.Model"),     -- a game.Session
--       Levels = require("apps.mygame.catalog.Levels"),
--       Stage = require("apps.mygame.controllers.StageController"), -- a game.Stage
--       Hud = require("apps.mygame.controllers.HudController"),     -- a game.Hud
--       BINDINGS = {buttons = {space = "fire"}}, -- optional, see game.Input
--   })
--
-- Every frame the SceneView calls `tick`: the session steps with the
-- current input, the stage and HUD templates render only if the session's
-- revision moved, and the stage receives the frame's poses. While the
-- game's window is closed or the scene is not on screen, SceneKit stops
-- calling, so nothing runs. Nothing here knows a game rule, a node or a
-- label.
local Input = require("game.Input")

local Game = {}
Game.__index = Game

-- A frame's measured interval is capped so a stalled run loop (a menu being
-- tracked, App Nap) resumes the game where it paused instead of leaping ahead.
Game.LOOP = {maxFrame = 0.1}

function Game:extend(class)
	class = class or {}
	class.__index = class
	setmetatable(class, {__index = self})
	class.new = function(options) return Game.create(class, options) end
	return class
end

-- `options.levels` replaces the level catalog (tests use small maps).
function Game.create(class, options)
	options = options or {}
	local self = setmetatable({model = class.Model.new(options.levels or class.Levels)}, class)
	self.input = Input.new({
		advance = function() self:advance() end,
		restart = function() self:restart() end,
	}, class.BINDINGS)
	return self
end

function Game:createWindow()
	local ns, xml = require("ns"), require("ui.xml")
	local config, refs = xml.renderFile(self.WINDOW, {
		actions = {restart = function() self:restart() end},
	})
	self.window = ns.Window(config)
	self.stage = self.Stage.new(refs.stage, ns, {
		key = function(_, key, pressed) return self.input:key(key, pressed) end,
		frame = function(_, dt) self:tick(dt) end,
		swipe = function(_, direction) self.input:swipe(direction) end,
		tap = function() self:tap() end,
	})
	self.hud = self.Hud.new(refs.hud, ns, {touch = ns.platform == "UIKit"})
	self:render()
	self.stage:pose(self.model:poses(), self.model:camera())
	return self.window
end

function Game:render()
	if self.rendered == self.model.revision then return end
	self.rendered = self.model.revision
	self.stage:render(self.model:scene())
	self.hud:render(self.model:status())
end

function Game:tick(dt)
	self.input:gamepad(self.stage:gamepad())
	-- Once the level ends, the tap button continues, like Return.
	if self.model.state ~= "playing" and self.input:take(self.input.bindings.tap) then self:advance() end
	self.model:step(math.min(dt, self.LOOP.maxFrame), self.input)
	self:render()
	self.stage:pose(self.model:poses(), self.model:camera())
end

-- A tap presses the tap button; after a level or game it continues, like
-- Return, so a touch screen needs no keyboard.
function Game:tap()
	if self.model.state ~= "playing" then self:advance() else self.input:press() end
end

function Game:advance()
	self.model:advance()
	self.input:reset()
	self:render()
end

function Game:restart()
	self.model:restart()
	self.input:reset()
	self:render()
end

return Game
