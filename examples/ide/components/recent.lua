local ns = require("AppKit")
local App = require("App")

local Recent = {}

function Recent.row(item, onOpenRecent)
	local icon = item.kind == "folder" and "folder" or "doc.text"
	return ns.Button {
		title = item.title or App.basename(item.path),
		subtitle = item.path,
		detail = App.describeRecent(item),
		systemImage = icon,
		style = "row",
		fixedHeight = 52,
		fillWidth = true,
		action = function()
			if onOpenRecent then
				onOpenRecent(item)
			end
		end,
	}
end

function Recent.section(title, emptyTitle, items, onOpenRecent)
	local children = {
		ns.HStack {
			fixedHeight = 43,
			paddingHorizontal = 20,
			alignment = "center",
			ns.Text {
				title,
				size = 11,
				weight = "semibold",
				color = "secondary",
			},
		},
		ns.Divider(),
	}

	if #items > 0 then
		children[#children + 1] = ns.ForEach(items, function(item, index, count)
			local row = Recent.row(item, onOpenRecent)
			if index == count then
				return row
			end
			return ns.Group {
				row,
				ns.HStack {
					fixedHeight = 1,
					spacing = 0,
					ns.Spacer { fixedWidth = 52 },
					ns.Divider(),
				},
			}
		end)
	else
		children[#children + 1] = ns.VStack {
			flexGrow = 1,
			alignment = "center",
			padding = 24,
			ns.Text {
				emptyTitle,
				size = 13,
				color = "secondary",
			},
		}
	end

	return ns.VStack {
		flexGrow = 1,
		spacing = 0,
		alignment = "leading",
		table.unpack(children),
	}
end

return Recent
