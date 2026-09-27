-- etlua partials report their own template errors, and xml.parse exposes
-- the parser to packages with their own vocabulary (modules/reel).
_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p " .. dir)
local function write(name, body)
	local file = assert(io.open(dir .. "/" .. name, "w"))
	file:write(body)
	file:close()
end

write("Good.etlua", [[<Item name="<%= name %>" />]])
write("Broken.etlua", [[<% this is not Lua %>]])
write("Parent.etlua", [[<List><%- partial("Good.etlua", { name = "a" }) %></List>]])
write("BadParent.etlua", [[<List><%- partial("Broken.etlua", {}) %></List>]])

local description = xml.describeFile(dir .. "/Parent.etlua", {})
t.expect(description.source:find('<Item name="a" />', 1, true) ~= nil, "a partial renders into its parent")

local ok, err = pcall(xml.describeFile, dir .. "/BadParent.etlua", {})
t.expect(not ok, "a broken partial fails its parent")
t.expect(tostring(err):find("Broken.etlua", 1, true) ~= nil, "the error names the broken partial")
t.expect(tostring(err):find("nil", 1, true) == nil or tostring(err):find("partial", 1, true) ~= nil,
	"the parent does not render the text nil in place of the partial")

local nodes = xml.parse([[<?xml version="1.0"?><Reel a="1"><Group b="x &amp; y"><Leaf /></Group></Reel>]])
t.assertEqual(#nodes, 1, "parse returns the root elements")
t.assertEqual(nodes[1].tag, "Reel", "parse keeps tags")
t.assertEqual(nodes[1].attrs.a, "1", "parse keeps attributes")
t.assertEqual(nodes[1].children[1].attrs.b, "x & y", "parse decodes entities")
t.assertEqual(nodes[1].children[1].children[1].tag, "Leaf", "parse nests children")

os.execute("rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
