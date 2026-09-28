_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local xml = require("ui.xml")
local Template = require("ui.template")

-- Reconciling a changed dimension rewrites all of a view's dimensions. One
-- the template leaves out must be cleared, not pinned to zero: a
-- maxWidth="infinity" strip whose height changes keeps filling its row.
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write([[<HStack spacing="10" maxWidth="infinity">
	<VStack width="<%= labels %>"><Label text="a" /></VStack>
	<VStack id="strip" maxWidth="infinity" height="<%= height %>" />
</HStack>]])
file:close()
local config, host = xml.render('<Window width="600" height="400"><VStack id="host" maxWidth="infinity" /></Window>', {}, ns)
local window = ns.Window(config)
local template = Template.new(host.host, path, ns)
local _, refs = template:update({height = 100, labels = 50})
local strip = refs.strip
local width = strip.frame.size.width
t.expect(width > 400, "the strip fills its row")
_, refs = template:update({height = 60, labels = 50})
t.expect(refs.strip == strip, "a height change patches the view in place")
t.assertEqual(strip.frame.size.height, 60, "to its new height")
t.assertEqual(strip.frame.size.width, width, "and keeps filling its row")
t.assertEqual(strip.fixedWidth, nil, "a width the template omits stays unset")
_, refs = template:update({height = 60, labels = 0})
t.assertEqual(refs.strip.frame.size.width, width + 50, "a zero width is still a real width")
window:close()
os.remove(path)

os.exit(t.summary() and 0 or 1)
