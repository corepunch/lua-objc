local Model = {}
Model.__index = Model

function Model.new(count)
	local self = setmetatable({ items = {} }, Model)
	for index = 1, count do
		self.items[index] = { id = index, title = "Item " .. index }
	end
	return self
end

return Model
