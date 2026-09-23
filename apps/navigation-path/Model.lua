local Model = {}

function Model.new()
	return { message = { type = "message", id = "welcome", title = "Welcome" } }
end

return Model
