-- Opens the window, draws the editor and turns presses, keys and menu
-- commands into model calls. Opening, exporting and auditioning go through
-- the injected audio service.
local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("apps.slicer.Model")
local Audio = require("apps.slicer.services.Audio")

local VIEWS = "apps/slicer/views/"

local Controller = {}
Controller.__index = Controller

-- `options.audio` replaces the plugin; `options.pickFile`, `options.pickFolder`
-- and `options.alert` replace the panels (tests).
function Controller.new(options)
	options = options or {}
	return setmetatable({
		model = options.model or Model.new(),
		audio = options.audio or Audio.new(),
		pickFile = options.pickFile or function() return ns.pickFile("Open Sound File", {types = {"public.audio"}}) end,
		pickFolder = options.pickFolder or function()
			return ns.pickFolder("Export Samples", {prompt = "Export", message = "Choose a folder for the slices."})
		end,
		alert = options.alert or function(title, message) ns.Alert {title = title, message = message} end,
	}, Controller)
end

function Controller:actions()
	if self.actionTable then return self.actionTable end
	local model = self.model
	local function edit(fn) return function(...) fn(...); self:render() end end
	self.actionTable = {
		open = function() local path = self.pickFile(); if path then self:open(path) end end,
		openDropped = function(paths) return paths and paths[1] ~= nil and self:open(paths[1]) end,
		export = function() self:export() end,
		play = function() self:play() end,
		stop = function() self:stop() end,
		addCut = edit(function(time) model:addCut(time) end),
		selectCut = edit(function(id) model:select(id) end),
		moveCut = edit(function(id, time) model:moveCut(id, time) end),
		deleteCut = edit(function() model:removeSelected() end),
		clearCuts = edit(function() model:clear() end),
		previousCut = edit(function() model:step(-1) end),
		nextCut = edit(function() model:step(1) end),
		setGrid = edit(function(index) model:setGrid(index + 1) end),
		zoomIn = edit(function() model:zoomBy(2, self:viewport()) end),
		zoomOut = edit(function() model:zoomBy(0.5, self:viewport()) end),
		key = function(key) return self:key(key) end,
		canExport = function() return model.path ~= nil end,
		hasCuts = function() return #model.cuts > 0 end,
		hasSelection = function() return model.selected ~= nil end,
		canZoomIn = function() return model:canZoomIn() end,
		canZoomOut = function() return model:canZoomOut() end,
	}
	return self.actionTable
end

-- Width of the visible part of the waveform.
function Controller:viewport()
	local scroll = self.content and self.content.refs and self.content.refs.scroll
	return scroll and scroll.contentSize.width or 0
end

-- Keys pressed while the waveform has focus.
function Controller:key(key)
	local handlers = {
		delete = "deleteCut", [" "] = "play", escape = "stop",
		left = "previousCut", right = "nextCut",
	}
	local action = handlers[key]
	if not action then return false end
	self:actions()[action]()
	return true
end

function Controller:open(path)
	local info, err = self.audio:info(path)
	if not info then
		self.alert("The file could not be opened.", err or path)
		return false
	end
	self:stop()
	self.model:open(path, info)
	self:render()
	return true
end

-- Play and Pause are one button: it pauses what is playing, resumes what
-- is paused, and otherwise plays the selected slice.
function Controller:play()
	local model = self.model
	local playback = model.playback
	if playback and playback.state == "playing" then
		self.audio:pause()
		model:setPlaybackState("paused")
	elseif playback then
		self.audio:resume()
		model:setPlaybackState("playing")
	else
		local slice = model.path and model:currentSlice()
		if not slice then return end
		local ok, err = self.audio:play(model.path, slice.start, slice.finish, function()
			model:stopPlayback()
			self:render()
		end)
		if not ok then self.alert("The slice could not be played.", err or ""); return end
		model:startPlayback(slice)
	end
	self:render()
end

function Controller:stop()
	self.audio:stop()
	if self.model.playback then
		self.model:stopPlayback()
		if self.content then self:render() end
	end
end

-- Writes every slice into a folder the person chooses. Returns the paths.
function Controller:export()
	local model = self.model
	if not model.path then return end
	local folder = self.pickFolder()
	if not folder then return end
	local slices, written = model:slices(), {}
	for _, slice in ipairs(slices) do
		local out = folder .. "/" .. model:fileName(slice.index, #slices)
		local frames, err = self.audio:export(model.path, slice.start, slice.finish, out)
		if not frames then
			self.alert("Slice " .. slice.index .. " could not be exported.", err or out)
			return written
		end
		table.insert(written, out)
	end
	if self.window then self.window.subtitle = string.format("Exported %d %s", #written, #written == 1 and "sample" or "samples") end
	if not _G.__headless and written[1] then ns.revealInFinder(written[1]) end
	return written
end

-- The toolbar is rendered again only when Play turns into Pause or back.
function Controller:render()
	local data = self.model:presentation()
	data.actions = self:actions()
	self.content:update(data)
	if self.window and self.shownPlaying ~= data.playing then
		self.shownPlaying = data.playing
		self.window:updateToolbar(xml.toolbarFile(VIEWS .. "layouts/Window.etlua", data))
	end
end

-- A sound file named on the command line (`./lua-objc apps/slicer loop.wav`).
local function launchFile(args)
	for index = 1, #(args or {}) do
		local value = args[index]
		if type(value) == "string" and not value:match("^%-") and not value:match("%.lua$")
			and value:lower():match("%.[%w]+$") and io.open(value) then
			return value
		end
	end
end

function Controller:createWindow()
	-- Files dropped on the Dock icon or opened with the app.
	ns.onOpenFiles(function(paths) if paths[1] then self:open(paths[1]) end end)
	local path = launchFile(rawget(_G, "arg"))
	if path then
		local info = self.audio:info(path)
		if info then self.model:open(path, info) end
	end
	local data = self.model:presentation()
	data.actions = self:actions()
	local config, refs = xml.renderFile(VIEWS .. "layouts/Window.etlua", data, ns)
	self.content = Template.new(refs.content, VIEWS .. "pages/Editor.etlua", ns)
	self:render()
	self.window = ns.Window(config)
	self.shownPlaying = data.playing
	return self.window
end

return Controller
