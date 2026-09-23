local Model = {}
Model.__index = Model

function Model.new()
	return setmetatable({
		materials = {
			{ name = "Regular", value = "regular" },
			{ name = "Clear", value = "clear" },
		},
	}, Model)
end

return Model
