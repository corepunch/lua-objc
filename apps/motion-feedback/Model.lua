local Model = {}

function Model.new()
	return setmetatable({ items = {}, nextId = 1 }, { __index = Model })
end

function Model:addItem()
	local item = { id = tostring(self.nextId), title = "Item " .. self.nextId }
	self.nextId = self.nextId + 1
	self.items[#self.items + 1] = item
	return item
end

return Model
