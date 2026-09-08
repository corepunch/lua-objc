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
	["text.long-ellipsis-italic"] = {
		title = "Text styles",
		body = "A deliberately long semantic text value that must truncate at the trailing edge",
	},
	["image.system-icon"] = {
		title = "Image",
		name = "star.fill",
		label = "Favorite",
	},
	["padding.vertical-edges"] = {
		title = "Padding",
		body = "Top and bottom edges",
	},
	["container.section-groupbox"] = {
		title = "Containers",
		body = "Nested native content",
	},
	["container.disclosure-expanded"] = {
		title = "Disclosure",
		body = "Expanded content",
	},
	["container.form-labeled-control-group"] = {
		title = "Form",
		body = "Native form content",
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
