-- Run with: ./lua-objc benchmarks/list.lua
-- Reports native construction and one initial layout, plus Lua heap delta. Use
-- /usr/bin/time -l for whole-process peak RSS. This does not measure frames.
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
	view.frame = ns.Rect(ns.Point(0, 0), ns.Size(800, 600))
	view:layout(800)
	local elapsed = os.clock() - started
	local memory = collectgarbage("count") - beforeMemory
	print(string.format("%s: %.3fs construction/layout, %.0f KiB Lua heap delta", label, elapsed, memory))
	return view
end

local requestedKind = os.getenv("LUA_OBJC_BENCH_KIND")
local requestedCount = tonumber(os.getenv("LUA_OBJC_BENCH_ROWS"))
local counts = requestedCount and { requestedCount } or { 1000, 5000 }
for _, count in ipairs(counts) do
	local items = makeRows(count)
	local template = [[<ScrollView><VStack><% for _, item in ipairs(items) do %><Label text="<%= item.title %>"/><% end %></VStack></ScrollView>]]
	if not requestedKind or requestedKind == "eager" then
		sample("eager VStack " .. count, function()
			return xml.render(template, { items = items }, ns)
		end)
	end
	if not requestedKind or requestedKind == "list" then
		sample("native List " .. count, function()
			return ns.List { columns = { { id = "title", title = "Title" } }, data = items }
		end)
	end
end
