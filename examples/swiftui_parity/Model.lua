local Model = {}

local CASES = {
	["text.single.default"] = {
		title = "Text",
		body = "Parity text",
	},
	["stack.h.spacing.default-text-spacer"] = {
		title = "HStack",
		left = "Left",
		right = "Right",
	},
	["button.standard.action-counter"] = {
		title = "Button",
		buttonTitle = "Activate",
	},
	["surface.background-rounded"] = {
		title = "Surface",
		body = "Native rounded surface",
	},
	["grid.two-by-two"] = {
		title = "Grid",
		cells = { "A1", "B1", "A2", "B2" },
	},
}

function Model.caseId()
	local requested = os.getenv("LUA_OBJC_PARITY_CASE")
	if requested and CASES[requested] then return requested end
	return "text.single.default"
end

function Model.data(caseId)
	local data = CASES[caseId]
	assert(data, "unknown parity case: " .. tostring(caseId))
	return data
end

return Model
