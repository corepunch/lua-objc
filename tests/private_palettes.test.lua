_G.__headless = true

local t = require("TestKit")
local xml = require("ui.xml")

local captured
local ns = setmetatable({}, { __index = function(_, kind)
	return function(props)
		if kind == "NavigationStack" then captured = props end
		return { kind = kind, props = props }
	end
end })

xml.render([[<NavigationStack title="Discover">
	<VStack><Label text="Content" /></VStack>
	<TopPalette><Label text="Top" /></TopPalette>
	<BottomPalette><Label text="Bottom" /></BottomPalette>
</NavigationStack>]], {}, ns)
t.assertEqual(captured.content.kind, "VStack", "navigation retains one content view")
t.assertEqual(captured.topPalette.kind, "Text", "top palette is a view")
t.assertEqual(captured.bottomPalette.kind, "Text", "bottom palette is a view")
t.expect(captured.enablePrivateNavigationPalettes == nil,
	"private palette opt-in defaults to false")

xml.render([[<NavigationStack enablePrivateNavigationPalettes="true">
	<Label text="Content" />
	<BottomPalette><Label text="Bottom" /></BottomPalette>
</NavigationStack>]], {}, ns)
t.expect(captured.enablePrivateNavigationPalettes == true,
	"explicit opt-in reaches the native navigation constructor")

local ok = pcall(function()
	xml.render([[<NavigationStack><Label text="Content" /><TopPalette /></NavigationStack>]], {}, ns)
end)
t.expect(not ok, "empty palette content is rejected")

os.exit(t.summary() and 0 or 1)
