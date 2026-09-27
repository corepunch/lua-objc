-- A partial that fails to compile or run must fail the template that
-- includes it and name the partial's path; it never renders as an empty
-- subtree. The apostrophe inside a Lua comment is the real-world trigger:
-- etlua's string scanner reads it as an unclosed string literal.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local viewdesc = require("ui.viewdesc")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p " .. dir)
local function write(name, body)
	local file = assert(io.open(dir .. "/" .. name, "w"))
	file:write(body)
	file:close()
end
local function expectFailure(ok, err, path, label)
	t.expect(not ok, label .. " raises")
	t.expect(tostring(err):find(dir .. "/" .. path, 1, true) ~= nil, label .. " names " .. path)
end

write("Parts.etlua", "<% -- Logic Pro's pads %>\n<Toggle id=\"x\" label=\"X\" />\n")
write("Main.etlua", "<VStack>\n<%- partial(\"Parts.etlua\", {}) %>\n</VStack>\n")
write("Good.etlua", "<VStack>\n<Toggle id=\"x\" label=\"X\" />\n</VStack>\n")
write("Runtime.etlua", "<% error(\"boom\") %><Label text=\"never\" />")
write("RuntimeParent.etlua", "<VStack><%- partial(\"Runtime.etlua\", {}) %></VStack>")
write("Outer.etlua", "<VStack><Label text=\"outer\" /><%- partial(\"Parts.etlua\", {}) %></VStack>")
write("NestedParent.etlua", "<VStack><%- partial(\"Outer.etlua\", {}) %></VStack>")
write("Layout.etlua", "<VStack><%- partial(\"Parts.etlua\", {}) %><%- yield(\"body\") %></VStack>")
write("Child.etlua", "<% extends(\"Layout.etlua\", {}) %><% block(\"body\", '<Label text=\"body\" />') %>")

-- Control: the same markup inline renders the toggle ref.
local _, goodRefs = xml.renderFile(dir .. "/Good.etlua", {}, ns)
t.expect(goodRefs.x ~= nil, "the toggle renders when it is not inside a broken partial")

local ok, view, refs = pcall(xml.renderFile, dir .. "/Main.etlua", {}, ns)
expectFailure(ok, view, "Parts.etlua", "renderFile with a partial that fails to compile")
t.expect(refs == nil, "a failed render returns no refs")
t.expect(tostring(view):find("failed to find string close", 1, true) ~= nil,
	"the error keeps etlua's compile diagnostic")

ok, view = pcall(xml.describeFile, dir .. "/RuntimeParent.etlua", {})
expectFailure(ok, view, "Runtime.etlua", "a partial that fails at runtime")
t.expect(tostring(view):find("boom", 1, true) ~= nil, "the runtime error message survives")

ok, view = pcall(xml.describeFile, dir .. "/NestedParent.etlua", {})
expectFailure(ok, view, "Parts.etlua", "a failing partial nested in another partial")

ok, view = pcall(xml.describeFile, dir .. "/Child.etlua", {})
expectFailure(ok, view, "Parts.etlua", "a failing partial inside an extends layout")
t.expect(tostring(view):find("Layout.etlua", 1, true) ~= nil, "the extends error names the layout")

-- viewdesc renders etlua directly; compile errors come back as nil plus a
-- message rather than a throw and must still fail.
ok, view = pcall(viewdesc.fromString, "<% -- it's %><Label text=\"x\" />", {})
t.expect(not ok, "viewdesc.fromString raises on an etlua compile error")
t.expect(tostring(view):find("viewdesc: template error", 1, true) ~= nil
	and tostring(view):find("failed to find string close", 1, true) ~= nil,
	"viewdesc reports the etlua diagnostic")

os.execute("rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
