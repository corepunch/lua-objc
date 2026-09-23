-- Run with: ./lua-objc benchmarks/list.lua
-- Reports Lua-side construction time and Lua heap delta. This is not a frame
-- rate or peak-process-memory benchmark; those require an on-device run.
_G.__headless = true

local ns = require("AppKit")
local xml = require("ui.xml")

local function makeRows(count)
	local result = {}
	for i = 1, count do result[i] = { id = i, title = "Item " .. i } end
	return result
end

local function sample(label, make)
	collectgarbage("collect")
	local beforeMemory = collectgarbage("count")
	local started = os.clock()
	local view = make()
	local elapsed = os.clock() - started
	local memory = collectgarbage("count") - beforeMemory
	print(string.format("%s: %.3fs, %.0f KiB Lua heap delta", label, elapsed, memory))
	return view
end

for _, count in ipairs({ 1000, 5000 }) do
	local items = makeRows(count)
	local template = [[<VStack><% for _, item in ipairs(items) do %><Label text="<%= item.title %>"/><% end %></VStack>]]
	sample("eager VStack " .. count, function()
		return xml.render(template, { items = items }, ns)
	end)
	sample("native List " .. count, function()
		return ns.List { columns = { { id = "title", title = "Title" } }, data = items }
	end)
end
