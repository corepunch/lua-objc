local Model = require("apps.studio.models.Rail")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({model = Model}, Controller)
end

function Controller:presentation(selected)
	local presentation = self.model.presentation(selected)
	self.modes = presentation.modes
	return presentation
end

-- Moves the rail highlight to the mode at `index`. Each mode renders a
-- selected and an unselected item; exactly one of the pair is visible.
function Controller:select(refs, index)
	local selected = self.model.modeAt(index)
	if not selected then return nil end
	for _, mode in ipairs(self.modes) do
		refs["rail/" .. mode.id .. "/on"].hidden = mode.id ~= selected
		refs["rail/" .. mode.id .. "/off"].hidden = mode.id == selected
	end
	return selected
end

return Controller
