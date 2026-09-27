-- Window captures and the layout they were taken from.
--
-- Each capture is `<name>.jpg`, a window-only screenshot at `scale` pixels
-- per point, and `<name>.layout.xml`, the `--dump-layout` of the same window
-- pruned to what a reel reads (see `Captures.pruneLayout`).
-- Pieces are cut by view identifier ("#treemap") or treemap cell
-- ("#treemap/developer") instead of hand-measured rectangles, so a layout
-- change in the app only needs fresh captures.
local xml = require("ui.xml")

local Captures = {}
Captures.__index = Captures

local Capture = {}
Capture.__index = Capture

-- open(dir, native, scale)
function Captures.open(dir, native, scale)
	return setmetatable({ dir = dir, native = native, scale = scale or 2, loaded = {} }, Captures)
end

function Captures:get(name)
	local capture = self.loaded[name]
	if not capture then
		capture = setmetatable({ name = name, set = self, pieces = {} }, Capture)
		self.loaded[name] = capture
	end
	return capture
end

local function number(value)
	return tonumber(value) or 0
end

-- Layout dumps write rectangles as "x y width height".
local function rect(value)
	local x, y, w, h = (value or ""):match("(%S+) (%S+) (%S+) (%S+)")
	return { x = number(x), y = number(y), w = number(w), h = number(h) }
end

-- Indexes identified views and treemap cells by the dump's window frames.
local function readLayout(path)
	local file = io.open(path, "r")
	if not file then error("reel: no layout dump " .. path .. " (run the capture step)", 0) end
	local source = file:read("a")
	file:close()
	local views, cells, rows = {}, {}, {}
	local function walk(nodes, owner)
		for _, node in ipairs(nodes) do
			if node.kind == "element" then
				local attrs = node.attrs
				if node.tag == "View" then
					local frame = rect(attrs.window)
					local id = attrs.identifier
					if id and not views[id] then views[id] = frame end
					-- Table rows belong to the nearest identified view (the
					-- scroll view of a <List>), in display order.
					if attrs.class == "NSTableRowView" and owner then
						rows[owner] = rows[owner] or {}
						table.insert(rows[owner], frame)
					end
					walk(node.children, id or owner)
				elseif node.tag == "TreemapCell" and owner then
					cells[owner] = cells[owner] or {}
					local cell = rect(attrs.window)
					cell.id, cell.depth, cell.label = attrs.id, number(attrs.depth), attrs.label
					table.insert(cells[owner], cell)
				else
					walk(node.children, owner)
				end
			end
		end
	end
	walk(xml.parse(source), nil)
	return views, cells, rows
end

local function escape(value)
	return (tostring(value):gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;")
		:gsub(">", "&gt;"):gsub("\n", "&#10;"))
end

-- Only these attributes are read back, in this order.
local keptAttributes = {
	View = { "class", "identifier", "window" },
	TreemapCell = { "id", "depth", "window", "label" },
}

-- pruneLayout(source) -> a `--dump-layout` reduced to what readLayout uses:
-- identified views, and the table rows and treemap cells owned by the
-- nearest identified view. A full window dump is mostly anonymous AppKit
-- wrappers; dropping them (their children move up to the nearest kept view)
-- keeps ownership and document order, so both read the same.
function Captures.pruneLayout(source)
	local function prune(nodes, owner, kept)
		for _, node in ipairs(nodes) do
			if node.kind == "element" then
				local attrs = node.attrs
				if node.tag == "View" then
					local id = attrs.identifier
					if id or (owner and attrs.class == "NSTableRowView") then
						local view = { tag = "View", attrs = attrs, children = {} }
						table.insert(kept, view)
						prune(node.children, id or owner, view.children)
					else
						prune(node.children, owner, kept)
					end
				elseif node.tag == "TreemapCell" then
					if owner then table.insert(kept, { tag = "TreemapCell", attrs = attrs, children = {} }) end
				else
					prune(node.children, owner, kept)
				end
			end
		end
		return kept
	end
	local lines = { '<?xml version="1.0" encoding="UTF-8"?>', "<Layout>" }
	local function write(nodes, depth)
		for _, node in ipairs(nodes) do
			local parts = { string.rep("  ", depth) .. "<" .. node.tag }
			for _, name in ipairs(keptAttributes[node.tag]) do
				local value = node.attrs[name]
				if value then table.insert(parts, name .. '="' .. escape(value) .. '"') end
			end
			local open = table.concat(parts, " ")
			if #node.children == 0 then
				table.insert(lines, open .. " />")
			else
				table.insert(lines, open .. ">")
				write(node.children, depth + 1)
				table.insert(lines, string.rep("  ", depth) .. "</" .. node.tag .. ">")
			end
		end
	end
	write(prune(xml.parse(source), nil, {}), 1)
	table.insert(lines, "</Layout>")
	return table.concat(lines, "\n") .. "\n"
end

function Capture:image()
	if not self.pixels then
		self.pixels = self.set.native.image(self.set.dir .. "/" .. self.name .. ".jpg", self.set.scale)
		self.width, self.height = self.pixels:size()
	end
	return self.pixels
end

function Capture:size()
	self:image()
	return self.width, self.height
end

function Capture:layout()
	if not self.viewFrames then
		self.viewFrames, self.cellFrames, self.rowFrames = readLayout(self.set.dir .. "/" .. self.name .. ".layout.xml")
	end
	return self.viewFrames, self.cellFrames, self.rowFrames
end

-- cells(viewId, depth) -> the treemap cells of a view, optionally one depth.
function Capture:cells(viewId, depth)
	local _, cells = self:layout()
	local list = {}
	for _, cell in ipairs(cells[viewId] or {}) do
		if depth == nil or cell.depth == depth then table.insert(list, cell) end
	end
	return list
end

-- rows(viewId) -> the table row frames under an identified view.
function Capture:rows(viewId)
	local _, _, rows = self:layout()
	return rows[viewId] or {}
end

-- rect(spec) -> x, y, w, h in window points. `spec` is "#view",
-- "#view/row/N" (the Nth table row under the view), "#view/cell" (a treemap
-- cell), "window" or "x, y, w, h".
function Capture:rect(spec)
	if spec == nil or spec == "window" then
		local w, h = self:size()
		return 0, 0, w, h
	end
	local rowView, rowIndex = spec:match("^#([^/]+)/row/(%d+)$")
	if rowView then
		local row = self:rows(rowView)[tonumber(rowIndex)]
		if not row then error("reel: " .. self.name .. " has no " .. spec, 0) end
		return row.x, row.y, row.w, row.h
	end
	local viewId, cellId = spec:match("^#([^/]+)/(.+)$")
	if viewId then
		for _, cell in ipairs(self:cells(viewId)) do
			if cell.id == cellId then return cell.x, cell.y, cell.w, cell.h end
		end
		error("reel: " .. self.name .. " has no cell " .. spec, 0)
	end
	viewId = spec:match("^#(.+)$")
	if viewId then
		local views = self:layout()
		local frame = views[viewId]
		if not frame then error("reel: " .. self.name .. " has no view " .. spec, 0) end
		return frame.x, frame.y, frame.w, frame.h
	end
	local x, y, w, h = spec:match("^%s*([%d.%-]+)%s*,%s*([%d.%-]+)%s*,%s*([%d.%-]+)%s*,%s*([%d.%-]+)%s*$")
	if not x then error("reel: bad rect " .. tostring(spec), 0) end
	return tonumber(x), tonumber(y), tonumber(w), tonumber(h)
end

-- sample(x, y) -> r, g, b of the capture at a window point.
function Capture:sample(x, y)
	local r, g, b = self:image():pixel(x, y)
	return r, g, b
end

-- piece(spec, options) -> sprite {image, x, y, w, h} in window points.
-- options.outset grows the rect; options.key = {x, y} keys out the colour
-- found at that window point, so the piece floats without its page;
-- options.downsample keeps that fraction of the pixels.
function Capture:piece(spec, options)
	options = options or {}
	local key = table.concat({ spec or "window", options.outset or 0,
		options.key and (options.key[1] .. "," .. options.key[2]) or "", options.downsample or 1,
		options.part and table.concat(options.part, ",") or "" }, "|")
	local sprite = self.pieces[key]
	if sprite then return sprite end
	local x, y, w, h = self:rect(spec)
	-- `part` is a sub-rectangle relative to the rect's origin.
	if options.part then x, y, w, h = x + options.part[1], y + options.part[2], options.part[3], options.part[4] end
	local outset = options.outset or 0
	x, y, w, h = x - outset, y - outset, w + outset * 2, h + outset * 2
	local image = self:image()
	-- Crops land on whole pixels; keep the sprite's point size in step with
	-- the pixels it actually holds so it never stretches.
	local scale = self.set.scale
	local px, py = math.floor(x * scale + 0.5), math.floor(y * scale + 0.5)
	local pw, ph = math.floor((x + w) * scale + 0.5) - px, math.floor((y + h) * scale + 0.5) - py
	local piece = (px == 0 and py == 0 and pw == self.width * scale and ph == self.height * scale)
		and image or image:cropPixels(px, py, pw, ph, scale)
	if options.key then
		local r, g, b = self:sample(options.key[1], options.key[2])
		piece = piece:keyed(r, g, b)
	end
	-- Sprites that only ever appear small can carry fewer pixels.
	if options.downsample then piece = piece:downsampled(options.downsample) end
	sprite = { image = piece, x = px / scale, y = py / scale, w = pw / scale, h = ph / scale }
	self.pieces[key] = sprite
	return sprite
end

-- import(native, screenshot, dump, output, appearance, expected) stores one
-- capture as `<output>.jpg` and `<output>.layout.xml`. The `--screenshot` PNG
-- (window plus shadow) becomes a window-only JPEG: the opaque window
-- rectangle, its rounded corners flattened onto a neutral colour for the
-- appearance (the renderer clips them again). The `--dump-layout` is pruned.
function Captures.import(native, screenshot, dump, output, appearance, expected)
	local image = native.image(screenshot, 1)
	local x, y, w, h = image:opaqueBounds(250 / 255)
	if not x then error("reel: " .. screenshot .. " has no opaque window", 0) end
	if expected and (w ~= expected[1] or h ~= expected[2]) then
		error(string.format("reel: %s: expected a %dx%d px window, found %dx%d", screenshot, expected[1], expected[2], w, h), 0)
	end
	local file = io.open(dump, "r")
	if not file then error("reel: no layout dump " .. dump, 0) end
	local layout = Captures.pruneLayout(file:read("a"))
	file:close()
	local neutral = appearance == "dark" and 0.12 or 0.93
	image:cropPixels(x, y, w, h):flattened(neutral, neutral, neutral, 1):write(output .. ".jpg", 0.82)
	file = assert(io.open(output .. ".layout.xml", "w"))
	file:write(layout)
	file:close()
end

return Captures
