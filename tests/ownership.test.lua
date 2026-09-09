_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

-- Weak Lua references observe handle collection without retaining the handles.
-- Native parents retain native children, not the original Lua userdata.
local handles = setmetatable({}, { __mode = "v" })
local parent = ns.VStack {}
do
	local child = ns.Text { "Retained by parent", fixedWidth = 120 }
	handles.original = child
	parent:add(child)
end
collectgarbage("collect")
collectgarbage("collect")
t.assertEqual(handles.original, nil, "native parent does not root Lua handle")
t.assertEqual(#parent.subviews, 1, "native parent retains child after Lua GC")

local child = parent.subviews[1]
t.assertEqual(child.text, "Retained by parent", "child remains readable after GC")
t.assertEqual(child.fixedWidth, 120, "native layout metadata outlives original handle")

-- Reading a native property creates another retained handle to the same object.
local alias = parent.subviews[1]
t.expect(not rawequal(child, alias), "native identity is distinct from Lua handle identity")
alias.text = "Changed through alias"
t.assertEqual(child.text, "Changed through alias", "handles share native property state")
t.assertEqual(child.fixedWidth, 120, "alias mutation preserves unrelated layout state")
handles.alias = alias
alias = nil
collectgarbage("collect")
collectgarbage("collect")
t.assertEqual(handles.alias, nil, "temporary alias is independently collectible")
t.assertEqual(child.text, "Changed through alias", "collecting alias preserves surviving handle")

parent:clearContainer()
t.assertEqual(#parent.subviews, 0, "container releases its child relationship")
collectgarbage("collect")
t.assertEqual(child.text, "Changed through alias", "Lua handle retains detached native child")
child.text = "Detached"
t.assertEqual(child.text, "Detached", "detached native child remains mutable")
t.assertEqual(child.fixedWidth, 120, "detaching preserves native layout metadata")

local other = ns.VStack { child }
child = nil
collectgarbage("collect")
collectgarbage("collect")
t.assertEqual(other.subviews[1].text, "Detached", "new parent retains reattached child")
t.assertEqual(#parent.subviews, 0, "reattaching leaves original parent empty")
other:clearContainer()
other:clearContainer()
t.assertEqual(#other.subviews, 0, "clearing an empty container is harmless")

os.exit(t.summary() and 0 or 1)
