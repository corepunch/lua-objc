local Difference = require("ui.reorder").Difference

local Model = {}
Model.__index = Model

function Model.new(count)
	local items = {}
	for index = 1, count do
		items[index] = { _id = index, title = "Item " .. index }
	end
	return setmetatable({ items = items }, Model)
end

function Model:applyReorder(difference)
	assert(getmetatable(difference) == Difference, "expected a reorder Difference")
	difference:apply(self.items)
end

return Model
