-- Templates are Lua, so they render in a sandbox: the template data, the
-- helpers and the pure standard functions, never io, os, require or load.
-- That is what lets an app's views be treated as data.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local function rejects(template, name)
	local ok, err = pcall(xml.render, template, {}, ns)
	t.expect(not ok, name .. " fails to render")
	return tostring(err)
end

for _, name in ipairs({ "io", "os", "require", "load", "loadstring", "dofile", "debug", "package", "_G" }) do
	rejects('<Label text="<%= ' .. name .. ' and "reachable" or "blocked" %>" />' ..
		'<% local _ = ' .. name .. '.x %>', "reaching " .. name)
end
rejects('<% io.open("/etc/hosts") %><Label text="x" />', "io.open")
rejects('<% os.execute("true") %><Label text="x" />', "os.execute")
rejects('<% require("os") %><Label text="x" />', "require")

-- Pure helpers still work, and data wins over a helper of the same name.
local label = xml.render([[<Label text="<%= string.upper("a") .. table.concat({1, 2}, "-") .. math.floor(2.5) .. #tostring(utf8.char(65)) %>" />
<% for _, n in ipairs({}) do end for k in pairs({}) do end %>]], {}, ns)
t.assertEqual(label.text, "A1-221", "string, table, math, utf8, ipairs and pairs are available")
local shadowed = xml.render('<Label text="<%= string %>" />', { string = "data" }, ns)
t.assertEqual(shadowed.text, "data", "template data comes before the helpers")

-- Partials and the helpers the framework injects keep working.
local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p " .. dir)
local file = assert(io.open(dir .. "/Part.etlua", "w"))
file:write('<Label text="<%= name %>" />')
file:close()
local view = xml.render('<VStack><%- partial("Part.etlua", { name = "inside" }) %></VStack>', { __baseDir = dir .. "/" }, ns)
t.assertEqual(view.subviews[1].text, "inside", "partial() is available in the sandbox")

-- A partial cannot escape either.
file = assert(io.open(dir .. "/Evil.etlua", "w"))
file:write('<% io.open("/etc/hosts") %><Label text="x" />')
file:close()
local ok = pcall(xml.render, '<VStack><%- partial("Evil.etlua", {}) %></VStack>', { __baseDir = dir .. "/" }, ns)
t.expect(not ok, "a partial is sandboxed too")
os.execute("rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
