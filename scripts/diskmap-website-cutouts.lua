-- Run after diskmap-website-capture.lua, from the repository root:
-- ./lua-objc scripts/diskmap-website-cutouts.lua
-- These are the same layout-addressed pieces and background key used by
-- reels/diskmap/views/Map.etlua and Cleanup.etlua. No app UI is redrawn.
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")
local xml = require("ui.xml")
local captures = Reel.captures("build/diskmap-website")
local output = "web/diskmap/assets/"

local function export(capture, rect, name, options)
	local piece = captures:get(capture):piece(rect, options)
	piece.image:write(output .. name .. ".png")
	print(name, piece.image:pixelSize())
end

export("map", "#sunburst", "map-cutout", { outset = 12, key = { 700, 300 } })
export("cleanup", "#rebuildableTile", "rebuildable-cutout")
export("cleanup", "#reviewTile", "review-cutout")
export("cleanup", "#checkedTile", "checked-cutout")
-- Export the native row rectangles themselves; the table's layout dump
-- supplies their geometry so a resized row never cuts through its content.
local function rows(captureName, listId, prefix, count)
	local file = assert(io.open("build/diskmap-website/" .. captureName .. ".layout.xml"))
	local nodes = xml.parse(file:read("a"))
	file:close()
	local found = 0
	local function walk(children, inList)
		for _, node in ipairs(children) do
			if node.kind == "element" then
				local selected = inList or node.attrs.identifier == listId
				if selected and node.attrs.class == "LuaTableRowView" and found < count then
					found = found + 1
					export(captureName, (node.attrs.window:gsub(" ", ", ")), prefix .. found)
				end
				walk(node.children, selected)
			end
		end
	end
	walk(nodes, false)
	assert(found == count, "Missing native rows in " .. listId)
end

rows("map", "mapList", "map-row-", 3)
rows("developer", "list_xcode", "developer-row-", 3)
os.exit(0)
