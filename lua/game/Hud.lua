-- The heads-up display over a game's stage: renders the game's HUD
-- template from the session's status. Unchanged labels keep their views
-- across renders. A game extends it with `viewData(status, hud)`:
--
--   local HudController = require("game.Hud"):extend({VIEW = "apps/mygame/views/sections/Hud.etlua"})
--   function HudController.viewData(status, hud) return {...} end
--
-- `hud.touch` says whether the device plays by touch, for the hint line.
local Template = require("ui.template")

local Hud = {}
Hud.__index = Hud

function Hud:extend(class)
	class = class or {}
	class.__index = class
	setmetatable(class, {__index = self})
	class.new = function(host, ns, options) return Hud.create(class, host, ns, options) end
	return class
end

function Hud.create(class, host, ns, options)
	return setmetatable({template = Template.new(host, class.VIEW, ns), touch = options and options.touch or false}, class)
end

function Hud:render(status)
	local _, refs = self.template:update(self.viewData(status, self))
	self.refs = refs
	return refs
end

return Hud
