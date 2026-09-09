local components = require("examples.adventure-arena.views.Components")
local text, stack = components.text, components.stack

return function(ns, adventures)
	local function tab(title, icon, content)
		return { __tab = true, title = title, systemImage = icon, content = content }
	end
	return ns.TabView { tabs = {
		tab("Adventures", "gamecontroller", adventures),
		tab("Ongoing", "clock.arrow.circlepath", ns.ContentUnavailable {
			title = "No Saved Games", systemImage = "clock.arrow.circlepath",
			description = "Start an adventure to begin playing.",
		}),
		tab("Create Game", "plus.circle", stack(ns, {
			text(ns, "Create a Game", { size = 30, weight = "bold" }),
			text(ns, "Bring your own ZIL adventure to the arena.", { color = "secondary" }),
		})),
		tab("Settings", "gearshape", stack(ns, {
			text(ns, "Settings", { size = 30, weight = "bold" }),
			text(ns, "Reading preferences and accessibility.", { color = "secondary" }),
		})),
	} }
end
