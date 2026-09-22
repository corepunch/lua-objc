local Tips = require("apps.diskmap.models.Tips")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, navigate)
	return setmetatable({model = model, navigate = navigate}, Controller)
end
function Controller:presentation(disk)
	local tips, actions = Tips.forInventory(self.model, disk), {}
	for _, tip in ipairs(tips) do actions["tip_" .. tip.id] = function() self.navigate(tip.action) end end
	return {tips = tips, actions = actions}
end
return Controller
