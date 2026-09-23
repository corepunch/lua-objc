local Difference = require("ui.reorder").Difference

local Model = {}
Model.__index = Model

local function makeItems(prefix)
	local result = {}
	for index = 1, 4 do
		result[index] = { _id = prefix .. index, title = prefix .. " " .. index }
	end
	return result
end

function Model.new()
	return setmetatable({
		stack = makeItems("Stack"),
		grid = makeItems("Grid"),
		flow = makeItems("Flow"),
	}, Model)
end

function Model:applyReorder(group, difference)
	assert(self[group], "unknown reorder group")
	assert(getmetatable(difference) == Difference, "expected a reorder Difference")
	difference:apply(self[group])
end

return Model
