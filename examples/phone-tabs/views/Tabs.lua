local ns  = require("ns")
local xml = require("ui.xml")

local VIEWS = "examples/phone-tabs/views/"

local function render(name, data)
	return xml.renderFile(VIEWS .. name, data, ns)
end

return function(model)
	return ns.TabView {
		tabs = {
			{
				__tab = true,
				title = "Home",
				systemImage = "house",
				content = render("Home.etlua", {
					recents = model.recents,
					featured = model.featured,
				}),
			},
			{
				__tab = true,
				title = "Search",
				systemImage = "magnifyingglass",
				content = render("Search.etlua", { favorites = model.favorites }),
			},
			{
				__tab = true,
				title = "Profile",
				systemImage = "person.crop.circle",
				content = render("Profile.etlua", { profile = model.profile }),
			},
		},
	}
end
