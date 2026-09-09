-- The same synchronous native contracts run in make test and the UIKit batch
-- host. They never substitute source-string checks for UIKit execution.
local M = {}

function M.run(ns)
	local count = 0
	local function equal(actual, expected, message)
		assert(actual == expected, message .. ": expected " .. tostring(expected)
			.. ", got " .. tostring(actual))
		count = count + 1
	end
	local function measure(view, width, height, target)
		local json = ns._parityMeasure(ns.ZStack { view }, {{ id = "node", view = target or view }},
			{ schema = 1, runId = "native-contract", id = "contract", width = width, height = height })
		return assert(ns._jsonParse(json)).probes[1]
	end
	local function intrinsic(children)
		return children
	end
	for _, kind in ipairs({ "HStack", "VStack", "ZStack" }) do
		local empty = ns[kind](intrinsic {})
		local p = measure(empty, 200, 100)
		equal(p.width, 0, kind .. " empty width")
		equal(p.height, 0, kind .. " empty height")
		equal(p.x, 100, kind .. " empty centered x")
		equal(p.y, 50, kind .. " empty centered y")
	end
	local a = ns.Text { "A", fixedWidth = 20, fixedHeight = 10 }
	local b = ns.Text { "B", fixedWidth = 40, fixedHeight = 20 }
	local row = ns.HStack(intrinsic { spacing = 8, a, b })
	local p = measure(row, 200, 100)
	for key, value in pairs({ width = 68, height = 20, x = 66, y = 40 }) do
		equal(p[key], value, "intrinsic row " .. key)
	end
	p = measure(row, 400, 200)
	equal(p.width, 68, "resize does not turn a previous frame into intrinsic width")
	equal(p.height, 20, "resize preserves intrinsic height")
	equal(p.x, 166, "resize recenters the row")
	a.hidden = true
	p = measure(row, 200, 100)
	equal(p.width, 40, "hidden siblings do not add spacing")
	equal(p.height, 20, "hidden sibling preserves other height")
	a.hidden = false
	p = measure(row, 200, 100)
	equal(p.width, 68, "unhide restores original spacing")
	local overlay = ns.ZStack(intrinsic {
		ns.Text { "small", fixedWidth = 10, fixedHeight = 10 },
		ns.Text { "large", fixedWidth = 80, fixedHeight = 40 },
	})
	p = measure(overlay, 200, 100)
	equal(p.width, 80, "overlay measures all siblings")
	equal(p.height, 40, "overlay height comes from largest sibling")
	local label = ns.Text { "A longer title", size = 13 }
	local before = measure(label, 300, 100)
	label.text = "A"
	local after = measure(label, 300, 100)
	equal(after.width < before.width, true, "shorter text shrinks after previous layout")
	equal(after.text, "A", "measurement reads mutated native text")
	label.text = "A longer title"
	equal(measure(label, 300, 100).width, before.width, "text sizing round-trip is stable")
	local wrapped = ns.Text { "A longer label that needs multiple lines", size = 20 }
	local wide = measure(wrapped, 600, 400)
	local narrow = measure(wrapped, 90, 400)
	equal(narrow.height > wide.height, true, "native text wraps under a narrow proposal")
	equal(narrow.width <= 90, true, "wrapped native text answers within proposed width")
	local restored = measure(wrapped, 600, 400)
	equal(restored.width, wide.width, "widening removes text wrapping")
	equal(restored.height, wide.height, "widening restores native line height")
	wrapped.text = "Short"
	local short = measure(wrapped, 90, 400)
	equal(short.height < narrow.height, true, "editing wrapped text removes obsolete lines")
	local nested = ns.VStack { wrapped }
	equal(measure(nested, 90, 400).height, short.height, "stack measures current text under same proposal")
	local zero = measure(ns.Text { "Zero", fixedWidth = 0, fixedHeight = 0 }, 200, 100)
	equal(zero.width, 0, "explicit zero width is preserved")
	equal(zero.height, 0, "explicit zero height is preserved")
	for _, kind in ipairs({ "HStack", "VStack" }) do
		local small = ns.Spacer { flexGrow = 1 }
		local large = ns.Spacer { flexGrow = 3 }
		local group = ns[kind] { spacing = 0, small, large }
		local dimension = kind == "HStack" and "width" or "height"
		equal(measure(group, 400, 400, small)[dimension], 100, kind .. " first weighted spacer")
		equal(measure(group, 400, 400, large)[dimension], 300, kind .. " second weighted spacer")
	end
	local changes, commands = {}, {}
	local field = ns.TextField { value = "Initial", placeholder = "Command",
		onChange = function(value) changes[#changes + 1] = value end,
		onCommand = function(command) commands[#commands + 1] = command; return command == "submit" end,
	}
	equal(field.text, "Initial", "text field value is independent of placeholder")
	equal(field.placeholder, "Command", "native placeholder is preserved")
	ns._textFieldTestInput(field, "look")
	equal(changes[1], "look", "native editing event dispatches new value")
	equal(ns._textFieldTestCommand(field, "submit"), true, "submit callback can handle keyboard return")
	equal(commands[1], "submit", "native command uses shared semantic name")
	equal(ns._textFieldTestCommand(field, "cancel"), false, "unhandled commands retain native behavior")
	equal(field.text, "look", "dispatch does not mutate field value")
	local top = ns.Text { "Top", fixedWidth = 20, fixedHeight = 10 }
	local bottom = ns.Text { "Bottom", fixedWidth = 20, fixedHeight = 10 }
	local padded = ns.VStack { paddingTop = 7, paddingBottom = 19, spacing = 0,
		fixedHeight = 100, top, ns.Spacer(), bottom }
	equal(measure(padded, 200, 100, top).y, 7, "asymmetric top padding uses top-left coordinates")
	equal(measure(padded, 200, 100, bottom).y, 71, "asymmetric bottom padding is independent")
	local filled = ns.Text { "Flexible", fillWidth = true, fixedHeight = 20 }
	local trailing = ns.Text { "Fixed", fixedWidth = 40, fixedHeight = 20 }
	local fillingRow = ns.HStack { spacing = 10, filled, trailing }
	equal(measure(fillingRow, 200, 100, filled).width, 150, "fillWidth consumes remaining row proposal")
	equal(measure(fillingRow, 200, 100, trailing).width, 40, "fillWidth preserves fixed sibling")
	local navigation = ns.NavigationStack { content = ns.Text "Home", title = "Home" }
	equal(navigation.depth, 1, "native navigation begins at root")
	navigation:push(ns.HostingController(ns.Text "Detail"), "Detail")
	equal(navigation.depth, 2, "native push adds one destination")
	equal(navigation.currentController.title, "Detail", "native push selects destination title")
	navigation:pop()
	equal(navigation.depth, 1, "native pop preserves root")
	equal(navigation.currentController.title, "Home", "native pop restores root title")
	navigation:pop()
	equal(navigation.depth, 1, "popping root keeps one controller")
	local button = ns.Button { title = "Open", fixedWidth = 100, fixedHeight = 100 }
	local overlay = ns.VStack { fillWidth = true, fillHeight = true, allowsHitTesting = false,
		ns.Text "Artwork caption" }
	local layered = ns.ZStack { fixedWidth = 100, fixedHeight = 100, button, overlay }
	measure(layered, 100, 100)
	equal(ns._hitTestTarget(layered, button, 50, 50), true, "decorative stack passes hit testing to native button")
	overlay.allowsHitTesting = true
	equal(ns._hitTestTarget(layered, button, 50, 50), false, "interactive stack receives hit testing")
	overlay.allowsHitTesting = false
	equal(ns._hitTestTarget(layered, button, 50, 50), true, "hit testing modifier round-trips")
	local artwork = ns.Image { path = "examples/adventure-arena/assets/planetfall.jpg", contentMode = "fill" }
	equal(artwork.contentModeName, "fill", "native image reports its actual content mode")
	artwork.contentModeName = "fit"
	equal(artwork.contentModeName, "fit", "image mode round-trips")
	local source = artwork.image
	artwork.image = nil
	equal(artwork.image, nil, "clearing native image clears rendered content")
	artwork.image = source
	equal(artwork.image ~= nil, true, "native image can be restored after clearing")
	return count
end

return M
