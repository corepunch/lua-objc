local Model = {}
function Model.rows()
	return {
		{ word = "door", verbs = { "Examine", "Open", "Close" } },
		{ word = "chest", verbs = { "Examine", "Open", "Close", "Take", "Push", "Pull", "Touch" } },
		{ word = "north", verbs = { "Go north" } },
	}
end
return Model
