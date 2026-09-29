-- Components found in simulator screenshots, which have no layout dump:
-- rows, cards, the filter, chat bubbles and diff lines, located by their
-- pixels when the reel loads, so recaptures never need re-measuring. The
-- reel cuts them out and animates them as components rather than showing
-- screenshots whole.
--
-- All rectangles are {x, y, w, h} in the screenshot's points.
local Regions = {}

local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 0.02) end

local function grey(r, g, b) return math.max(r, g, b) - math.min(r, g, b) < 0.03 end

-- bands(image, x0, x1, y0, y1, background(r, g, b) -> bool, gap) -> {{y, h}}:
-- horizontal runs of rows holding anything but background, merged across
-- gaps of fewer than `gap` points.
function Regions.bands(image, x0, x1, y0, y1, background, gap)
	local bands, open, last = {}, nil, nil
	for y = y0, y1 do
		local content = false
		for x = x0, x1, 2 do
			local r, g, b = image:pixel(x, y)
			if not background(r, g, b) then content = true; break end
		end
		if content then
			if open and y - last <= (gap or 4) then last = y
			else
				if open then table.insert(bands, { y = open, h = last - open + 1 }) end
				open, last = y, y
			end
		end
	end
	if open then table.insert(bands, { y = open, h = last - open + 1 }) end
	return bands
end

-- ── Todo on the iPhone ───────────────────────────────────────────────────

-- The task list's geometry: rows span the content column, a divider under
-- each; the progress card fills the column in the grouped background; the
-- segmented filter is narrower. In points on a 402 × 874 screen.
local TODO = { left = 28, right = 374, top = 150, bottom = 860, statusBar = 54, divider = { 0.78, 0.95 } }

local function isWhite(r, g, b) return r > 0.985 and g > 0.985 and b > 0.985 end
local function isCard(r, g, b) return near(r, 0.949, 0.012) and near(g, 0.949, 0.012) and near(b, 0.969, 0.012) end

-- A divider row: the column is one light grey from edge to edge, with
-- white just above and below it (a card's fill is grey for many rows).
local function divider(image, y)
	local mid = (TODO.left + TODO.right) / 2
	if not isWhite(image:pixel(mid, y - 2)) or not isWhite(image:pixel(mid, y + 2)) then return false end
	local first
	for x = TODO.left + 40, TODO.right - 4, 6 do
		local r, g, b = image:pixel(x, y)
		if not grey(r, g, b) or r < TODO.divider[1] or r > TODO.divider[2] then return false end
		first = first or r
		if not near(r, first, 0.02) then return false end
	end
	return true
end

-- todo(image, rows) -> parts: {status, header, filter?, progress?,
-- completed?, ["task/<id>"] = rect…} for a Todo screenshot whose visible
-- rows, top to bottom, are the task ids in `rows` (from the app's model).
function Regions.todo(image, rows)
	local parts = {}
	parts.status = { x = 0, y = 0, w = 402, h = TODO.statusBar }
	-- Dividers under rows.
	local dividers = {}
	for y = TODO.top, TODO.bottom do
		if divider(image, y) and (#dividers == 0 or y - dividers[#dividers] > 3) then table.insert(dividers, y) end
	end
	if #dividers ~= #rows then
		error(string.format("regions: found %d row dividers for %d rows", #dividers, #rows), 0)
	end
	-- A row's height is the smallest gap between dividers.
	local height = math.huge
	for i = 2, #dividers do height = math.min(height, dividers[i] - dividers[i - 1]) end
	if #dividers == 1 then height = 53 end
	for i, id in ipairs(rows) do
		parts["task/" .. id] = { x = TODO.left - 6, y = dividers[i] - height + 1, w = TODO.right - TODO.left + 12, h = height }
	end
	-- A gap taller than a row holds the "Completed" label.
	for i = 2, #dividers do
		if dividers[i] - dividers[i - 1] > height * 1.3 then
			parts.completed = { x = TODO.left - 4, y = dividers[i - 1] + 4, w = 160, h = dividers[i] - height - dividers[i - 1] - 4 }
		end
	end
	-- Blocks in the grouped background above the rows: the progress card
	-- reaches the column's right edge, the filter does not.
	local firstRow = dividers[1] - height
	-- Below the heading, anything not white across the filter's width is a
	-- block (a selected segment is white, so one column is not enough).
	local blocks = Regions.bands(image, TODO.left + 8, TODO.left + 200, TODO.top, firstRow - 2, isWhite, 2)
	for _, band in ipairs(blocks) do
		if band.h > 20 then
			local r, g, b = image:pixel(TODO.right - 8, band.y + band.h / 2)
			local rect = { x = TODO.left - 2, y = band.y - 2, w = TODO.right - TODO.left + 4, h = band.h + 4 }
			if isCard(r, g, b) then parts.progress = rect
			else rect.w = 220; parts.filter = rect end
		end
	end
	-- The heading: title and date, between the status bar and the first block.
	local topOfContent = parts.filter and parts.filter.y or (parts.progress and parts.progress.y or firstRow)
	parts.header = { x = TODO.left - 6, y = TODO.statusBar + 20, w = 300, h = topOfContent - TODO.statusBar - 26 }
	return parts
end

-- ── Lua Studio's chat on the iPad ────────────────────────────────────────

-- The conversation column (right of the stage), above the composer.
local CHAT = { left = 470, right = 1370, top = 100, bottom = 930, background = { 1, 1, 1 } }

local function isAccent(r, g, b) return b > 0.8 and r < 0.3 and g > 0.35 and g < 0.65 end

-- chat(image) -> {turns = {{kind = "user"|"text"|"card", rect}…},
-- lines = {rect…} (diff lines inside cards)}: the conversation's pieces,
-- top to bottom.
function Regions.chat(image)
	local out = { turns = {}, lines = {} }
	local bands = Regions.bands(image, CHAT.left, CHAT.right, CHAT.top, CHAT.bottom, isWhite, 6)
	for _, band in ipairs(bands) do
		-- Classify by what the band holds: a run of blue is a bubble (the
		-- agent's sparkle is blue too, but small), grey a card, else text.
		local accent, card = 0, false
		local minX, maxX = math.huge, -math.huge
		local middle = band.y + math.floor(band.h / 2)
		for x = CHAT.left, CHAT.right, 4 do
			local r, g, b = image:pixel(x, middle)
			if isAccent(r, g, b) then accent = accent + 1 end
			if isCard(r, g, b) then card = true end
			for _, y in ipairs({ band.y + 1, middle, band.y + band.h - 2 }) do
				if not isWhite(image:pixel(x, y)) then minX = math.min(minX, x); maxX = math.max(maxX, x) end
			end
		end
		local kind = accent > 12 and "user" or ((card and band.h > 60) and "card" or "text")
		local rect = { x = minX - 6, y = band.y - 3, w = maxX - minX + 12, h = band.h + 6 }
		table.insert(out.turns, { kind = kind, rect = rect })
		if kind == "card" then
			-- Diff lines: text runs inside the card, on the card's grey.
			local cardLeft = CHAT.left + 140
			for _, line in ipairs(Regions.bands(image, cardLeft, CHAT.right - 120, band.y + 60, band.y + band.h - 4,
				function(r, g, b) return isCard(r, g, b) or isWhite(r, g, b) end, 3)) do
				table.insert(out.lines, { x = cardLeft - 20, y = line.y - 3, w = CHAT.right - cardLeft - 80, h = line.h + 6, card = rect })
			end
		end
	end
	return out
end

return Regions
