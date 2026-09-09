local components = require("examples.adventure-arena.views.Components")

return function(ns, game, transcript, actions)
	local output = ns.Text { transcript, size = 16, lineLimit = 0, fillWidth = true }
	local field = ns.TextField { placeholder = "What do you want to do?", fillWidth = true,
		accessibilityLabel = "Command", onCommand = function(command)
			if command ~= "submit" then return false end
			actions.submit()
			return true
		end,
	}
	local root = ns.VStack { fillWidth = true, fillHeight = true, spacing = 8,
		ns.ScrollView { content = components.stack(ns, { output }) },
		ns.HStack { paddingHorizontal = 16, fillWidth = true,
			field, ns.Button { title = "Send", action = actions.submit },
		},
		ns.HStack { paddingHorizontal = 16, paddingBottom = 8, fillWidth = true,
			ns.ForEach({ "look", "inventory" }, function(command)
				return ns.Button { title = command, action = function() actions.command(command) end }
			end),
			ns.Spacer(), ns.Button { title = "End session", action = actions.close },
		},
	}
	return root, { input = field, output = output }
end
