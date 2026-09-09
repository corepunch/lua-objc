local components = require("examples.adventure-arena.views.Components")
local text, stack, rating = components.text, components.stack, components.rating

return function(ns, game, actions)
	return ns.ScrollView { vertical = true, horizontal = false,
		content = stack(ns, {
			ns.Image { path = game.cover, fillWidth = true, fixedHeight = 280,
			contentMode = "fill", cornerRadius = 16 },
			text(ns, game.title, { size = 30, weight = "bold", lines = 2 }),
			ns.HStack { spacing = 8,
				text(ns, game.genres[1], { size = 12, color = "secondary" }),
				text(ns, game.author, { size = 12, color = "secondary" }),
				text(ns, tostring(game.year), { size = 12, color = "secondary" }),
			},
			rating(ns, game), ns.Separator(),
			text(ns, "About this Game", { size = 21, weight = "bold" }),
			text(ns, game.description, { size = 16, color = "secondary", lineLimit = 0 }),
			ns.Button { title = "Play Adventure", action = function() actions.play() end },
			ns.Button { title = "Back to Adventures", action = function()
				actions.back()
			end },
		}),
	}
end
