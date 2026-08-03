local Model = {}

Model.navigationItems = {
	{ _id = "overview", section = "Overview" },
	{ _id = "activity", section = "Activity" },
	{ _id = "reports",  section = "Reports" },
	{ _id = "settings", section = "Settings" },
}

Model.contentItems = {
	{ _id = "1", item = "Declarative layout", owner = "Core",   status = "Ready", section = "overview" },
	{ _id = "2", item = "Native tables",     owner = "AppKit",  status = "Ready", section = "overview" },
	{ _id = "3", item = "Measurement pass",  owner = "Core",    status = "New",   section = "activity" },
	{ _id = "4", item = "Flexible sizing",   owner = "Core",    status = "New",   section = "activity" },
	{ _id = "5", item = "Export pipeline",   owner = "Data",    status = "New",   section = "reports" },
	{ _id = "6", item = "User preferences",  owner = "UX",      status = "Ready", section = "settings" },
}

function Model.itemsForSection(sectionId)
	local result = {}
	for _, item in ipairs(Model.contentItems) do
		if item.section == sectionId then
			result[#result + 1] = item
		end
	end
	return result
end

return Model
