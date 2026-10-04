-- Coin Quest's root controller: creates the window, runs the game loop and
-- coordinates the focused controllers.
--
-- Every frame the SceneView calls `tick`: the session steps with the
-- current input, the stage and HUD templates render only if the session's
-- revision moved, and the stage receives the frame's poses. Nothing here
-- knows a game rule, a node or a label.
local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.coin-quest.Model")
local Levels = require("apps.coin-quest.catalog.Levels")
local InputController = require("apps.coin-quest.controllers.InputController")
local StageController = require("apps.coin-quest.controllers.StageController")
local HudController = require("apps.coin-quest.controllers.HudController")

local VIEWS = "apps/coin-quest/views/"

-- A frame's measured interval is capped so a stalled run loop (a menu being
-- tracked, App Nap) resumes the game where it paused instead of leaping ahead.
local LOOP = {maxFrame = 0.1}

local Controller = {}
Controller.__index = Controller

-- `options.levels` replaces the level catalog (tests use small maps).
function Controller.new(options)
	options = options or {}
	local self = setmetatable({model = Model.new(options.levels or Levels)}, Controller)
	self.input = InputController.new({
		advance = function() self:advance() end,
		restart = function() self:restart() end,
	})
	return self
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {
		actions = {restart = function() self:restart() end},
	})
	self.window = ns.Window(config)
	self.stage = StageController.new(refs.stage, ns, {
		key = function(_, key, pressed) return self.input:key(key, pressed) end,
		frame = function(_, dt) self:tick(dt) end,
		swipe = function(_, direction) self.input:swipe(direction) end,
		tap = function() self:tap() end,
	})
	self.hud = HudController.new(refs.hud, ns, {touch = ns.platform == "UIKit"})
	self:render()
	self.stage:pose(self.model:poses(), self.model:camera())
	return self.window
end

function Controller:render()
	if self.rendered == self.model.revision then return end
	self.rendered = self.model.revision
	self.stage:render(self.model:scene())
	self.hud:render(self.model:status())
end

function Controller:tick(dt)
	self.input:gamepad(self.stage:gamepad())
	-- Once the level ends, a jump continues, like Return.
	if self.model.state ~= "playing" and self.input:takeJump() then self:advance() end
	self.model:step(math.min(dt, LOOP.maxFrame), self.input)
	self:render()
	self.stage:pose(self.model:poses(), self.model:camera())
end

-- A tap jumps; after a level or game it continues, like Return, so a
-- touch screen needs no keyboard.
function Controller:tap()
	if self.model.state ~= "playing" then self:advance() else self.input:jump() end
end

function Controller:advance()
	self.model:advance()
	self.input:reset()
	self:render()
end

function Controller:restart()
	self.model:restart()
	self.input:reset()
	self:render()
end

return Controller
