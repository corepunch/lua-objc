local Theme = require("apps.studio.helpers.Theme")
local Model = {}

function Model.presentation()
	return {
		device = "iPhone 16",
		zoom = "100%",
		runLabel = "Run",
		tint = Theme.tint,
	}
end

return Model
