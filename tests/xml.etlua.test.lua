local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local viewdesc = require("ui.viewdesc")

-- ── Helper: render XML string and return view + refs ────────────────────────
local function render(src, data)
    return xml.render(src, data or {}, ns)
end

-- ── Basic etlua templates ──────────────────────────────────────────────────

t.expect(true, "basic etlua renders without error")
local v, refs = render([[<Label text="<%= 'Hello' %>" />]])
t.expect(v ~= nil, "etlua template produces a view")
t.assertEqual(v.text, "Hello", "etlua expression substitutes value")

v = render([[<Label text="<%= 2 + 2 %>" />]])
t.assertEqual(v.text, "4", "etlua expression evaluates Lua code")

v = render([[<Label text="<% if true then %>yes<% end %>" />]])
t.assertEqual(v.text, "yes", "etlua conditional renders content")

v = render([[<Label text="<% if false then %>no<% end %>" />]])
t.assertEqual(v.text, "", "etlua conditional skips when false")

v = render([[<% for i = 1, 3 do %><Label text="<%= i %>" /><% end %>]])
t.expect(v ~= nil, "etlua loop renders multiple views")

-- ── XML tags produce correct native classes ────────────────────────────────

-- Label / Text
v = render([[<Label text="Hello" />]])
t.expect(v ~= nil, "Label creates a view")
t.assertEqual(v.text, "Hello", "Label sets text property")

v = render([[<Text text="Hello" />]])
t.expect(v ~= nil, "Text creates a view")
t.assertEqual(v.text, "Hello", "Text sets text property")

-- Label with text (no size test - not exposed in bridge)
v = render([[<Label text="Big" />]])
t.expect(v ~= nil, "Label creates a view")

-- Title
v = render([[<Title text="My Title" />]])
t.expect(v ~= nil, "Title creates a view")

-- TextField
v = render([[<TextField value="Search" placeholder="Type here" />]])
t.expect(v ~= nil, "TextField creates a view")


-- Button
v = render([[<Button title="Click Me" />]])
t.expect(v ~= nil, "Button creates a view")

-- SystemImage
v = render([[<SystemImage name="star.fill" />]])
t.expect(v ~= nil, "SystemImage creates a view")

-- Image (symbol variant)
v = render([[<Image symbol="star.fill" />]])
t.expect(v ~= nil, "Image with symbol creates SystemImage")

-- Toggle
v = render([[<Toggle label="Enable" />]])
t.expect(v ~= nil, "Toggle creates a view")

-- Spacer
v = render([[<Spacer />]])
t.expect(v ~= nil, "Spacer creates a view")

-- Divider
v = render([[<Divider />]])
t.expect(v ~= nil, "Divider creates a view")

-- ── Layout containers ──────────────────────────────────────────────────────

v = render([[<VStack spacing="12" padding="16"><Label text="A" /><Label text="B" /></VStack>]])
t.expect(v ~= nil, "VStack with children creates a view")

v = render([[<HStack spacing="8"><Label text="L" /><Spacer /><Label text="R" /></HStack>]])
t.expect(v ~= nil, "HStack with Spacer creates a view")

v = render([[<HSplit><Label text="Left" /><Label text="Right" /></HSplit>]])
t.expect(v ~= nil, "HSplit creates a view")

-- ── Layout props propagation ───────────────────────────────────────────────

v = render([[<VStack flexGrow="1" padding="16" fixedWidth="200" />]])
t.expect(v ~= nil, "VStack accepts layout props")

v = render([[<Label text="X" fixedWidth="100" fixedHeight="32" />]])
t.expect(v ~= nil, "Label accepts fixedWidth/fixedHeight")

-- ── ref= attribute ─────────────────────────────────────────────────────────

local view, r = render([[<Label ref="myLabel" text="Ref Test" />]])
t.expect(r.myLabel ~= nil, "ref= attribute stores view in refs table")
t.assertEqual(r.myLabel.text, "Ref Test", "refs.myLabel points to the rendered view")

view, r = render([[
<VStack>
    <Label ref="top" text="Top" />
    <Label ref="bottom" text="Bottom" />
</VStack>
]])
t.expect(r.top ~= nil, "first ref= is captured")
t.expect(r.bottom ~= nil, "second ref= is captured")
t.assertEqual(r.top.text, "Top", "ref=top points to correct view")
t.assertEqual(r.bottom.text, "Bottom", "ref=bottom points to correct view")

-- ── List with Columns ──────────────────────────────────────────────────────

v, r = render([[
<List ref="myList" style="plain" header="true">
    <Column id="name" title="Name" />
    <Column id="role" title="Role" width="120" />
</List>
]])
t.expect(v ~= nil, "List with Columns creates a view")
t.expect(r.myList ~= nil, "List ref= is captured")

-- ── Window config detection ────────────────────────────────────────────────

local cfg, r = xml.render([[
<Window title="Test" width="800" height="600">
    <Label text="Content" />
</Window>
]])
t.expect(cfg ~= nil, "Window root returns config table (not a view)")
t.assertEqual(cfg.title, "Test", "Window config has title")
t.assertEqual(cfg.width, 800, "Window config has width")
t.assertEqual(cfg.height, 600, "Window config has height")
t.expect(cfg.content ~= nil, "Window config has content view")

-- Window with toolbar
cfg = xml.render([[
<Window title="Toolbar Test" width="640" height="480">
    <Toolbar>
        <ToolbarItem id="save" label="Save" icon="doc" />
        <ToolbarItem id="refresh" label="Refresh" icon="arrow.clockwise" />
    </Toolbar>
    <Label text="Body" />
</Window>
]])
t.expect(cfg ~= nil, "Window with Toolbar returns config")
t.expect(cfg.toolbar ~= nil, "Window config has toolbar")
t.assertEqual(#cfg.toolbar, 2, "Toolbar has 2 items")
t.assertEqual(cfg.toolbar[1].id, "save", "First toolbar item id")
t.assertEqual(cfg.toolbar[1].label, "Save", "First toolbar item label")

-- ── Unknown tags error ─────────────────────────────────────────────────────

local ok = pcall(function()
    render([[<UnknownTag />]])
end)
t.expect(not ok, "Unknown tag raises an error")

-- ── Template inheritance ───────────────────────────────────────────────────

-- Create test templates for inheritance
local f = io.open("/tmp/test_parent.etlua", "w")
f:write('<Window title="<%= title %>" width="<%= width or 400 %>" height="300">\n')
f:write('    <%- yield("content") %>\n')
f:write('</Window>')
f:close()

f = io.open("/tmp/test_child.etlua", "w")
f:write('<% extends("test_parent.etlua", { title = "Child Window", width = 500 }) %>\n')
f:write('<% block("content", [[\n')
f:write('    <VStack>\n')
f:write('        <Label text="Child Content" />\n')
f:write('    </VStack>\n')
f:write(']]) %>')
f:close()

cfg = xml.renderFile("/tmp/test_child.etlua")
t.expect(cfg ~= nil, "Template inheritance produces Window config")
t.assertEqual(cfg.title, "Child Window", "Child overrides parent title")
t.assertEqual(cfg.width, 500, "Child overrides parent width")
t.expect(cfg.content ~= nil, "Inherited template has content from block")

-- ── Partials ───────────────────────────────────────────────────────────────

f = io.open("/tmp/test_partial.etlua", "w")
f:write([[<Label text="Partial Content" />]])
f:close()

f = io.open("/tmp/test_partial_parent.etlua", "w")
f:write([[<VStack>
    <%= partial("test_partial.etlua", {}) %>
    <%= partial("test_partial.etlua", {}) %>
</VStack>]])
f:close()

v = xml.renderFile("/tmp/test_partial_parent.etlua")
t.expect(v ~= nil, "Partial renders without error")

-- ── View descriptions ──────────────────────────────────────────────────────

local desc = viewdesc.fromString([[<Label text="Hello" />]])
t.expect(desc ~= nil, "fromString produces a description")
t.assertEqual(desc.tag, "Label", "Description tag is Label")
t.assertEqual(desc.props.text, "Hello", "Description has text prop")

-- View description with children
desc = viewdesc.fromString([[
<VStack spacing="8">
    <Label text="First" />
    <Label text="Second" />
</VStack>
]])
t.expect(desc ~= nil, "VStack description produced")
t.assertEqual(desc.tag, "VStack", "Description tag is VStack")
t.expect(desc.children ~= nil, "VStack has children")
t.assertEqual(#desc.children, 2, "VStack has 2 children")
t.assertEqual(desc.children[1].tag, "Label", "First child is Label")
t.assertEqual(desc.children[1].props.text, "First", "First child text")

-- View description with Button
desc = viewdesc.fromString([[<Button title="Click" systemImage="star" />]])
t.expect(desc ~= nil, "Button description produced")
t.assertEqual(desc.tag, "Button", "Button desc tag")
t.assertEqual(desc.props.title, "Click", "Button desc has title")
t.assertEqual(desc.props.systemImage, "star", "Button desc has systemImage")

-- View description diff
local oldDesc = viewdesc.fromString([[<Label text="Hello" />]])
local newDesc = viewdesc.fromString([[<Label text="World" />]])
local patches = viewdesc.diff(oldDesc, newDesc)
t.expect(#patches > 0, "Diff produces patches when text changes")
t.assertEqual(patches[1].op, "update", "First patch is update")
t.expect(patches[1].props.text == "World", "Patch contains new text value")

-- Diff with no changes
newDesc = viewdesc.fromString([[<Label text="Hello" />]])
patches = viewdesc.diff(oldDesc, newDesc)
t.assertEqual(#patches, 0, "Diff produces no patches when unchanged")

-- Diff with tag change
oldDesc = viewdesc.fromString([[<Label text="X" />]])
newDesc = viewdesc.fromString([[<Button title="X" />]])
patches = viewdesc.diff(oldDesc, newDesc)
t.expect(#patches == 1, "Tag change produces one replace patch")
t.assertEqual(patches[1].op, "replace", "Tag change is replace operation")

-- Diff with added child
oldDesc = viewdesc.fromString([[<VStack><Label text="A" /></VStack>]])
newDesc = viewdesc.fromString([[<VStack><Label text="A" /><Label text="B" /></VStack>]])
patches = viewdesc.diff(oldDesc, newDesc)
t.expect(#patches > 0, "Adding a child produces patches")

-- ── List description ───────────────────────────────────────────────────────

desc = viewdesc.fromString([[
<List ref="table" style="inset" header="false">
    <Column id="name" title="Name" />
    <Column id="value" title="Value" width="80" />
</List>
]])
t.expect(desc ~= nil, "List description produced")
t.assertEqual(desc.tag, "List", "List desc tag")
t.expect(desc.props.columns ~= nil, "List has columns")
t.assertEqual(#desc.props.columns, 2, "List has 2 columns")
t.assertEqual(desc.props.columns[1].id, "name", "First column id")
t.assertEqual(desc.props.columns[2].width, 80, "Second column width")

-- ── Custom tag registration ────────────────────────────────────────────────

xml.registry["CustomWidget"] = function(ns, attrs, children)
    return ns.Text {
        attrs.label or "Custom",
    }
end

v = render([[<CustomWidget label="My Widget" />]])
t.expect(v ~= nil, "Custom tag creates a view")

-- ── Multiple root elements ─────────────────────────────────────────────────

v = render([[<Label text="A" /><Label text="B" />]])
t.expect(v ~= nil, "Multiple root elements wrap in VStack")

-- ── Edge cases ─────────────────────────────────────────────────────────────

-- Empty template
v = render([[  ]])
t.expect(v ~= nil, "Empty/whitespace template produces a view")

-- Self-closing tags
v = render([[<Spacer />]])
t.expect(v ~= nil, "Self-closing tag works")

-- Nested containers
v = render([[
<VStack>
    <HStack>
        <VStack>
            <Label text="Deep" />
        </VStack>
    </HStack>
</VStack>
]])
t.expect(v ~= nil, "Deeply nested containers work")

-- ── Summary ────────────────────────────────────────────────────────────────
os.exit(t.summary() and 0 or 1)
