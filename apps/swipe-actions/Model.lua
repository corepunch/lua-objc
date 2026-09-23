local Model = {}
Model.__index = Model

function Model.new(items)
	local rows = items or {
		{ id = "1", title = "First item" },
		{ id = "2", title = "Second item" },
		{ id = "3", title = "Third item" },
	}
	return setmetatable({
		items = rows,
		stackItems = {
			{ id = "a", title = "Plan weekend", status = "" },
			{ id = "b", title = "Review notes", status = "" },
		},
	}, Model)
end

function Model:setStackStatus(id, status)
	for _, item in ipairs(self.stackItems) do
		if item.id == id then
			item.status = status
			return item
		end
	end
end

function Model:removeAt(index, id)
	local item = self.items[index]
	if not item or item.id ~= id then return false end
	table.remove(self.items, index)
	return true
end

return Model
