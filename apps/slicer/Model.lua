-- The open sound file and the cuts placed on it. A cut is a time in seconds;
-- the slices are the pieces between the file's start, the cuts and its end,
-- numbered from the start as they are drawn and exported. Grid and zoom are
-- the editor's settings, kept with the file they apply to.
local Model = {}
Model.__index = Model

-- Snap steps per beat, in the toolbar picker's order. 0 places cuts freely.
Model.grids = {
	{title = "1/4", division = 1},
	{title = "1/8", division = 2},
	{title = "1/16", division = 4},
	{title = "1/32", division = 8},
	{title = "Off", division = 0},
}
-- The closest zoom, in points per bar: a 1/32 step is then 64 points wide.
Model.maxZoom = 2048

-- `zoom` is points per bar; nil fits the whole file in the window.
function Model.new()
	return setmetatable({bpm = 140, beatsPerBar = 4, grid = 3, cuts = {}, nextId = 1}, Model)
end

-- `info` is {duration, sampleRate, channels} from the audio service.
function Model:open(path, info)
	self.path, self.info, self.zoom = path, info, nil
	self.cuts, self.selected, self.nextId = {}, nil, 1
end

function Model:duration() return self.info and self.info.duration or 0 end

function Model:barSeconds() return 60 / self.bpm * self.beatsPerBar end

function Model:division() return Model.grids[self.grid].division end

function Model:bars() return self:duration() / self:barSeconds() end

-- Width of the waveform in points at the current zoom, or nil to fit.
function Model:width()
	if not self.zoom or not self.info then return nil end
	return math.floor(self:bars() * self.zoom + 0.5)
end

-- Scales the zoom by `factor` from what a `viewport` points wide shows now.
-- Zooming out until the file fits returns to fitting the window.
function Model:zoomBy(factor, viewport)
	local bars = self:bars()
	if bars <= 0 or viewport <= 0 then return end
	local zoom = math.min(Model.maxZoom, (self.zoom or viewport / bars) * factor)
	self.zoom = zoom * bars > viewport and zoom or nil
end

function Model:canZoomIn() return self.info ~= nil and (self.zoom or 0) < Model.maxZoom end

function Model:canZoomOut() return self.zoom ~= nil end

function Model:setGrid(index) self.grid = math.max(1, math.min(#Model.grids, index)) end

function Model:find(id)
	for index, cut in ipairs(self.cuts) do
		if cut.id == id then return cut, index end
	end
end

-- Adds a cut at `time` and selects it; a cut already there is selected
-- instead, so clicking a grid line twice does not stack two cuts.
function Model:addCut(time)
	time = math.max(0, math.min(self:duration(), time))
	for _, cut in ipairs(self.cuts) do
		if math.abs(cut.time - time) < 1e-6 then self.selected = cut.id; return cut.id end
	end
	local id = "cut" .. self.nextId
	self.nextId = self.nextId + 1
	table.insert(self.cuts, {id = id, time = time})
	self.selected = id
	return id
end

function Model:moveCut(id, time)
	local cut = self:find(id)
	if cut then cut.time = math.max(0, math.min(self:duration(), time)) end
	self.selected = id
end

function Model:select(id)
	self.selected = self:find(id) and id or nil
end

function Model:removeSelected()
	local _, index = self:find(self.selected)
	if not index then return false end
	table.remove(self.cuts, index)
	self.selected = nil
	return true
end

function Model:clear()
	self.cuts, self.selected = {}, nil
end

-- Cuts in time order.
function Model:sorted()
	local cuts = {}
	for _, cut in ipairs(self.cuts) do table.insert(cuts, cut) end
	table.sort(cuts, function(a, b) return a.time < b.time end)
	return cuts
end

-- Selects the cut before (-1) or after (1) the selected one, or the first.
function Model:step(direction)
	local cuts = self:sorted()
	if #cuts == 0 then return end
	local current
	for index, cut in ipairs(cuts) do
		if cut.id == self.selected then current = index end
	end
	local index = current and math.max(1, math.min(#cuts, current + direction)) or (direction > 0 and 1 or #cuts)
	self.selected = cuts[index].id
end

-- The pieces between the start, the cuts and the end, without empty ones.
function Model:slices()
	local slices, duration = {}, self:duration()
	local start = 0
	local function add(finish)
		if finish > start then table.insert(slices, {index = #slices + 1, start = start, finish = finish}) end
		start = math.max(start, finish)
	end
	for _, cut in ipairs(self:sorted()) do add(math.min(cut.time, duration)) end
	add(duration)
	return slices
end

-- The slice the selected cut starts, else the first.
function Model:currentSlice()
	local cut = self:find(self.selected)
	local slices = self:slices()
	for _, slice in ipairs(slices) do
		if cut and math.abs(slice.start - cut.time) < 1e-9 then return slice end
	end
	return slices[1]
end

-- "Break 03.wav" for slice 3 of Break.aif; the number is padded to the
-- width of the slice count so the files sort in order.
function Model:fileName(index, count)
	local base = (self.path or "Sample"):match("([^/]+)$"):gsub("%.[^.]*$", "")
	local digits = math.max(2, #tostring(count))
	return string.format("%s %0" .. digits .. "d.wav", base, index)
end

local function clock(seconds)
	return string.format("%d:%06.3f", math.floor(seconds / 60), seconds % 60)
end

-- What the editor page shows.
function Model:presentation()
	local slices = self:slices()
	local data = {
		path = self.path,
		bpm = self.bpm,
		beatsPerBar = self.beatsPerBar,
		division = self:division(),
		grid = self.grid - 1,
		grids = Model.grids,
		width = self:width(),
		selected = self.selected or "",
		cuts = self:sorted(),
	}
	if self.info then
		data.name = self.path:match("([^/]+)$")
		data.summary = string.format("%d %s · %s · %d BPM, %d/4", #slices, #slices == 1 and "slice" or "slices",
			clock(self:duration()), self.bpm, self.beatsPerBar)
		local slice = self:currentSlice()
		data.sliceSummary = slice and string.format("Slice %d: %s – %s", slice.index, clock(slice.start), clock(slice.finish)) or ""
	end
	return data
end

return Model
