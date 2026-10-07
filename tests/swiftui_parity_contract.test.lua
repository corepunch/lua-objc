-- Contract for skills/swiftui-parity. Every tag the skill names must exist
-- in xml.schema. This does not prove native layout; it stops the skill from
-- documenting a tag the renderer will reject.
local t = require("TestKit")
local xml = require("ui.xml")

local tags = {
	"VStack", "HStack", "ZStack", "HSplit", "Spacer", "ScrollView",
	"Grid", "GridRow", "Section", "GroupBox", "Form", "LabeledContent",
	"ControlGroup", "DisclosureGroup", "FlowStack", "LazyVStack", "LazyVGrid",
	"SafeAreaInset", "Label", "Title", "Paragraph", "TextField", "SearchField",
	"TextEditor", "Hyperlink", "Link", "Button", "Toggle", "Slider", "Stepper",
	"Picker", "Option", "DatePicker", "ColorPicker", "Menu", "MenuItem",
	"List", "Column", "SwipeRow", "OutlineView", "Toolbar", "ToolbarItem",
	"ToolbarSpacer", "TabView", "Tab", "TabAccessory", "NavigationStack",
	"NavigationLink", "Page", "Sheet", "TopPalette", "BottomPalette", "Window",
	"ContentUnavailable", "ProgressView", "Gauge", "Divider", "PageControl",
	"Image", "SystemImage", "MaterialView", "GlassEffect", "GlassEffectContainer",
	"LinearGradient", "MeshGradient", "WebView", "Chart",
}

t.expect(type(xml.schema) == "table", "xml.schema is exported")
for _, tag in ipairs(tags) do
	t.expect(xml.schema[tag] ~= nil, "swiftui-parity tag is registered: " .. tag)
end

t.assertEqual(xml.aliases.Text, "Label", "Text remains an alias for Label")
t.expect(xml.schema.Label.props.color ~= nil, "Label schema records color")
t.expect(xml.schema.Button.props.foregroundStyle ~= nil, "Button schema records foregroundStyle")

os.exit(t.summary() and 0 or 1)
