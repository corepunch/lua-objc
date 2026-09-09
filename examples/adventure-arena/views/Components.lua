local function text(ns, value, props)
	props = props or {}
	props.fillWidth = true
	props[1] = value
	return ns.Text(props)
end

local function stack(ns, children, padding, spacing)
	children.padding = padding or 20
	children.spacing = spacing or 14
	children.fillWidth = true
	return ns.VStack(children)
end

local function rating(ns, game)
	return ns.HStack { spacing = 5,
		ns.ForEach({ 1, 2, 3, 4, 5 }, function(index)
			return ns.SystemImage { index <= math.floor(game.rating) and "star.fill"
				or (index - game.rating <= 0.5 and "star.leadinghalf.filled" or "star"),
				size = 13, color = "yellow", accessibilityLabel = tostring(game.rating) .. " out of 5" }
		end),
		text(ns, string.format("%.1f", game.rating), { size = 12, color = "secondary" }),
	}
end

return { text = text, stack = stack, rating = rating }
