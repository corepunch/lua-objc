-- Window captures and the layout they were taken from.
--
-- Each capture is what `lua-objc --capture=<dir>/<name>` writes from one
-- settled moment of an app window: `<name>.png`, the window's content view
-- at backing scale, and `<name>.layout.xml`, its layout dump, whose `scale`
-- attribute gives the image's pixels per point. Pieces are cut by view
-- identifier ("#treemap"), table row ("#list/row/2") or treemap cell
-- ("#treemap/developer") instead of hand-measured rectangles, so a layout
-- change in the app only needs fresh captures. Anything a reel asks for that
-- a capture lacks is an error, raised while the reel loads where possible,
-- rather than a piece that silently never appears.
local xml = require("ui.xml")

local Captures = {}
Captures.__index = Captures

local Capture = {}
Capture.__index = Capture

-- open(dir, native, hint): `hint` says how to make missing captures; by
-- default a `lua-objc --capture` command.
function Captures.open(dir, native, hint)
	return setmetatable({ dir = dir, native = native, hint = hint, loaded = {} }, Captures)
end

local function exists(path)
	local file = io.open(path, "r")
	if file then file:close() end
	return file ~= nil
end

-- get(name) -> a capture; both of its files must exist.
function Captures:get(name)
	local capture = self.loaded[name]
	if not capture then
		local base = self.dir .. "/" .. name
		local missing = {}
		for _, path in ipairs({ base .. ".png", base .. ".layout.xml" }) do
			if not exists(path) then table.insert(missing, path) end
		end
		if #missing > 0 then
			error("reel: capture " .. name .. " is missing " .. table.concat(missing, " and ")
				.. " (" .. (self.hint or ("write it with lua-objc --capture=" .. base)) .. ")", 0)
		end
		capture = setmetatable({ name = name, set = self, base = base, pieces = {} }, Capture)
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

-- Reads the root size, the scale, identified views, and the table rows and
-- treemap cells owned by the nearest identified view, in document order.
local function readLayout(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("a")
	file:close()
	local layout = { views = {}, cells = {}, rows = {} }
	local function walk(nodes, owner)
		for _, node in ipairs(nodes) do
			if node.kind == "element" then
				local attrs = node.attrs
				if node.tag == "Layout" then
					layout.scale = tonumber(attrs.scale)
					walk(node.children, owner)
				elseif node.tag == "View" then
					local frame = rect(attrs.window)
					layout.root = layout.root or frame
					local id = attrs.identifier
					if id and not layout.views[id] then layout.views[id] = frame end
					-- Table rows belong to the nearest identified view (the
					-- scroll view of a <List>), in display order.
					if attrs.class == "NSTableRowView" and owner then
						layout.rows[owner] = layout.rows[owner] or {}
						table.insert(layout.rows[owner], frame)
					end
					walk(node.children, id or owner)
				elseif node.tag == "TreemapCell" and owner then
					layout.cells[owner] = layout.cells[owner] or {}
					local cell = rect(attrs.window)
					cell.id, cell.depth, cell.label = attrs.id, number(attrs.depth), attrs.label
					table.insert(layout.cells[owner], cell)
				else
					walk(node.children, owner)
				end
			end
		end
	end
	walk(xml.parse(source), nil)
	if not layout.scale or not layout.root then
		error("reel: " .. path .. " is not a lua-objc --capture layout (no scale or root view)", 0)
	end
	return layout
end

function Capture:layout()
	self.parsed = self.parsed or readLayout(self.base .. ".layout.xml")
	return self.parsed
end

-- The image must be the layout's root at the layout's scale, or every cut
-- would land in the wrong place.
function Capture:image()
	if not self.pixels then
		local layout = self:layout()
		local pixels = self.set.native.image(self.base .. ".png", layout.scale)
		local pw, ph = pixels:pixelSize()
		local ew, eh = math.floor(layout.root.w * layout.scale + 0.5), math.floor(layout.root.h * layout.scale + 0.5)
		if pw ~= ew or ph ~= eh then
			error(string.format("reel: %s.png is %dx%d px but its layout expects %dx%d px", self.base, pw, ph, ew, eh), 0)
		end
		self.pixels = pixels
	end
	return self.pixels
end

-- size() -> the window's width and height in points.
function Capture:size()
	local root = self:layout().root
	return root.w, root.h
end

local function view(capture, viewId)
	local frame = capture:layout().views[viewId]
	if not frame then error("reel: " .. capture.name .. " has no view #" .. tostring(viewId), 0) end
	return frame
end

-- An unknown view, or one with no cells (at that depth), is an error.
function Capture:cells(viewId, depth)
	view(self, viewId)
	local list = {}
	for _, cell in ipairs(self:layout().cells[viewId] or {}) do
		if depth == nil or cell.depth == depth then table.insert(list, cell) end
	end
	if #list == 0 then
		error("reel: " .. self.name .. " has no treemap cells in #" .. viewId
			.. (depth and (" at depth " .. depth) or ""), 0)
	end
	return list
end

-- rows(viewId) -> the table row frames under an identified view; an unknown
-- view or one with no rows is an error.
function Capture:rows(viewId)
	view(self, viewId)
	local rows = self:layout().rows[viewId]
	if not rows then error("reel: " .. self.name .. " has no table rows in #" .. viewId, 0) end
	return rows
end

-- row(viewId, n) -> the Nth row frame; a missing row is an error.
function Capture:row(viewId, n)
	local row = self:rows(viewId)[n]
	if not row then
		error(string.format("reel: %s has no row %s in #%s (%d rows)", self.name, tostring(n), viewId, #self:rows(viewId)), 0)
	end
	return row
end

-- rect(spec) -> x, y, w, h in window points. `spec` is "#view" (any
-- identifier, even one containing "/"),
-- "#view/row/N" (the Nth table row under the view), "#view/cell" (a treemap
-- cell), "window" or "x, y, w, h".
function Capture:rect(spec)
	if spec == nil or spec == "window" then
		local w, h = self:size()
		return 0, 0, w, h
	end
	-- An identifier may itself contain "/" (an app's "task/2"); a view with
	-- the whole name wins over the row and cell forms.
	local whole = spec:match("^#(.+)$")
	local exact = whole and self:layout().views[whole]
	if exact then return exact.x, exact.y, exact.w, exact.h end
	local rowView, rowIndex = spec:match("^#([^/]+)/row/(%d+)$")
	if rowView then
		local row = self:row(rowView, tonumber(rowIndex))
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
		local frame = view(self, viewId)
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
	local scale = self:layout().scale
	local px, py = math.floor(x * scale + 0.5), math.floor(y * scale + 0.5)
	local pw, ph = math.floor((x + w) * scale + 0.5) - px, math.floor((y + h) * scale + 0.5) - py
	local iw, ih = image:pixelSize()
	local piece = (px == 0 and py == 0 and pw == iw and ph == ih)
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

return Captures
