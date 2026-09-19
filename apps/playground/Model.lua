local Model = {}
Model.__index = Model
function Model.new()
	return setmetatable({ count = 0 }, Model)
end
function Model:increment()
	self.count = self.count + 1
end
return Model
