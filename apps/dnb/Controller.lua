local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.dnb.Model")
local Synth = require("apps.dnb.models.Synth")
local Visuals = require("apps.dnb.models.Visuals")
local Styles = require("apps.dnb.host.Styles")
local Visualizers = require("apps.dnb.host.Visualizers")
local AudioOutput = require("apps.dnb.services.AudioOutput")

local VIEWS = "apps/dnb/views/"

-- The queue is the latency between moving a control and hearing it. The
-- display loop refills it and animates the visualizer at about 60 Hz, which
-- leaves many refills of headroom before the device would run dry.
local PLAYBACK = {sampleRate = 44100, bufferSeconds = 0.3, frameInterval = 1 / 60}

local SECTION_TITLES = {intro = "Intro", build = "Build-up", drop = "Drop", breakdown = "Breakdown",
	outro = "Outro", halftime = "Half-time", blend = "Mixing in"}

local Controller = {}
Controller.__index = Controller

-- `options` lets tests inject an output, seed, style and scheduler.
function Controller.new(options)
	options = options or {}
	local style = Styles:get(options.style or Styles:list()[1].id)
	local model = Model.new(options.seed or os.time(), style)
	local self = setmetatable({
		model = model,
		style = style,
		synth = Synth.new(model, PLAYBACK.sampleRate, style.sound),
		output = options.output or AudioOutput.new(PLAYBACK.sampleRate,
			math.floor(PLAYBACK.sampleRate * PLAYBACK.bufferSeconds)),
		async = options.async or ns.async,
		sleep = options.sleep or ns.sleep,
		buffer = {},
		playing = false,
		visuals = Visuals.new(Visualizers:list()),
		stages = setmetatable({}, {__mode = "k"}), -- the stage each open view last received
		showing = setmetatable({}, {__mode = "k"}), -- the scenes each open view last drew
	}, Controller)
	self.composer = Styles:create(style.id, model.seed)
	self.synth:setComposer(self.composer)
	return self
end

-- Now-playing text for a bar, or for the first bar before playback starts.
function Controller:nowPlaying(bar, fraction)
	local playing = bar ~= nil
	bar = bar or self.composer:bar(0, self.model)
	local title = bar.blend and "blend" or bar.halftime and "halftime" or bar.section
	return {
		section = playing and SECTION_TITLES[title] or "Ready to play",
		detail = string.format("Track %d · %s · %s · %s", bar.track + 1, bar.style, bar.key, bar.progression),
		position = string.format("Bar %d of %d", bar.sectionBar + 1, bar.sectionLength),
		progress = (bar.sectionBar + (fraction or 0)) / bar.sectionLength,
		tempo = self.model:formatted("tempo"):match("%d+"),
	}
end

function Controller:partGroups()
	local groups = {}
	for _, group in ipairs(Model.partGroups) do
		local parts = {}
		for _, part in ipairs(group.parts) do
			table.insert(parts, {id = part.id, label = self.model:label(part.id), on = self.model:enabled(part.id),
				supported = self.model:supports(part.id)})
		end
		table.insert(groups, {title = group.title, parts = parts})
	end
	return groups
end

function Controller:controlGroups()
	local groups = {}
	for _, group in ipairs(Model.controlGroups) do
		local controls = {}
		for _, control in ipairs(group.controls) do
			local min, max = self.model:range(control.id)
			table.insert(controls, {id = control.id, label = control.label, min = min, max = max,
				value = self.model:value(control.id), text = self.model:formatted(control.id)})
		end
		table.insert(groups, {title = group.title, controls = controls})
	end
	return groups
end

function Controller:viewData()
	return {
		title = self.style.title,
		subtitle = self.style.summary,
		styles = Styles:list(),
		styleIndex = Styles:index(self.style.id) - 1,
		scenes = Visualizers:list(),
		sceneIndex = self.visuals.pinned and self.visuals.pinned + 1 or 0,
		program = Visualizers.program(),
		nowPlaying = self:nowPlaying(),
		partGroups = self:partGroups(),
		controlGroups = self:controlGroups(),
		actions = self:actions(),
	}
end

function Controller:actions()
	local actions = {
		play = function() self:play() end,
		stop = function() self:stop() end,
		nextTrack = function() self:nextTrack() end,
		newSet = function() self:newSet() end,
		selectStyle = function(index) self:selectStyle(index) end,
		selectScene = function(index) self:selectScene(index) end,
		openMiniPlayer = function() self:openMiniPlayer() end,
		closeMiniPlayer = function() self:closeMiniPlayer() end,
		miniPlayerClosed = function() self:miniPlayerClosed() end,
	}
	for _, group in ipairs(Model.partGroups) do
		for _, part in ipairs(group.parts) do
			actions["part_" .. part.id] = function(on) self.model:setEnabled(part.id, on) end
		end
	end
	for _, group in ipairs(Model.controlGroups) do
		for _, control in ipairs(group.controls) do
			actions["control_" .. control.id] = function(value) self:setControl(control.id, value) end
		end
	end
	return actions
end

-- Refs of every open window: the main one and, when open, the mini player.
function Controller:views()
	local views = {}
	if self.refs then table.insert(views, self.refs) end
	if self.mini then table.insert(views, self.mini.refs) end
	return views
end

function Controller:setControl(id, value)
	self.model:setValue(id, value)
	local label = self.refs and self.refs["value_" .. id]
	if label then label.text = self.model:formatted(id) end
	if id == "tempo" and self.refs then self.refs.tempo.text = self.model:formatted(id):match("%d+") end
end

-- A style plugin takes over at the next bar line with its own set, sound,
-- tempo range and control defaults; the pads show what it plays.
function Controller:selectStyle(index)
	local style = assert(Styles:list()[index + 1], "no style " .. tostring(index))
	if style == self.style then return end
	self.style = style
	self.model:setStyle(style)
	self.composer = Styles:create(style.id, self.model.seed)
	self.synth:setComposer(self.composer, Synth.sound(style.sound))
	local refs = self.refs
	if not refs then return end
	self.window.title, self.window.subtitle = style.title, style.summary
	for _, group in ipairs(self:partGroups()) do
		for _, part in ipairs(group.parts) do
			local toggle = refs["part_" .. part.id]
			toggle.title, toggle.enabled = part.label, part.supported
		end
	end
	for _, group in ipairs(self:controlGroups()) do
		for _, control in ipairs(group.controls) do
			local slider = refs["control_" .. control.id]
			slider.minValue, slider.maxValue, slider.doubleValue = control.min, control.max, control.value
			refs["value_" .. control.id].text = control.text
		end
	end
	refs.tempo.text = self.model:formatted("tempo"):match("%d+")
	if not self.playing then self:showIdle() end
end

-- 0 is Automatic: the director picks scenes by section and phrase.
function Controller:selectScene(index)
	self.visuals:pin(index > 0 and index - 1 or nil)
end

-- Tops the output queue up with freshly synthesized audio.
function Controller:pump()
	local frames = self.output:space()
	if frames <= 0 then return 0 end
	self.synth:render(self.buffer, frames)
	self.output:write(self.buffer, frames)
	return frames
end

-- The main view rect (see Visuals.fullStage): the visualizer between the
-- safe area's top, under the toolbar, and the top of the panels over its
-- bottom. It is measured from the layout because the panels keep their
-- height as the window resizes, so the stage's share of the view changes.
function Controller:stage(refs)
	local view = refs.visualizer.frameInWindow
	local width, height = view.size.width, view.size.height
	if width <= 0 or height <= 0 then return Visuals.fullStage end
	-- Window coordinates grow upward from the bottom-left.
	local function below(frame) return view.origin.y + height - (frame.origin.y + frame.size.height) end
	local top = math.max(0, below(refs.content.frameInWindow))
	local bottom = math.min(height, below(refs.panels.frameInWindow))
	if bottom <= top then return Visuals.fullStage end
	return {x = 0, y = top / height, width = 1, height = (bottom - top) / height}
end

local function sameStage(a, b)
	return a and b and a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
end

-- One display frame: refill audio while playing, then follow the playhead
-- in the header and the visualizers. A resting picture is sent again only
-- when a resize moves its stage.
function Controller:tick(dt)
	if self.playing then self:pump() end
	local played = self.playing and self.output:played() or nil
	local bar = played and self.synth:barAt(played)
	if bar then self:showPlayhead(bar, played) end
	local views, stages, moved = self:views(), {}, false
	for i, refs in ipairs(views) do
		stages[i] = self:stage(refs)
		moved = moved or not sameStage(stages[i], self.stages[refs])
	end
	if not self.playing and self.visuals:settled() and not moved then return end
	local bands, rms
	if self.playing then bands, rms = self.output:spectrum(Visuals.bands) end
	self.visuals:update({bands = bands, rms = rms, playing = self.playing, bar = bar,
		played = played, sampleRate = PLAYBACK.sampleRate, gain = self.model:value("volume")}, dt)
	for i, refs in ipairs(views) do
		self:present(refs, stages[i])
		self.stages[refs] = stages[i]
	end
end

-- Sends a view the current picture: its values every frame, and the scene
-- draws whenever the scenes on its layers change.
function Controller:present(refs, stage)
	refs.visualizer.values = self.visuals:pack(stage)
	local layers = self.visuals:layers()
	local key = table.concat(layers, ",")
	if self.showing[refs] ~= key then
		refs.visualizer.draws = Visualizers.draws(layers)
		self.showing[refs] = key
	end
end

function Controller:showPlayhead(bar, played)
	local info = self:nowPlaying(bar, math.max(0, math.min(1, (played - bar.frame) / bar.frames)))
	for _, refs in ipairs(self:views()) do
		if refs.section.text ~= info.section then refs.section.text = info.section end
		if refs.detail.text ~= info.detail then refs.detail.text = info.detail end
		if refs.position and refs.position.text ~= info.position then refs.position.text = info.position end
		if refs.progress then refs.progress.doubleValue = info.progress end
	end
end

-- The header while stopped: the first bar of the current set.
function Controller:showIdle()
	local info = self:nowPlaying(self.composer:bar(self.synth.composerBar, self.model))
	for _, refs in ipairs(self:views()) do refs.detail.text = info.detail end
end

function Controller:setTransport(playing)
	self.playing = playing
	for _, refs in ipairs(self:views()) do
		refs.play.enabled = not playing
		refs.stop.enabled = playing
	end
end

function Controller:play()
	if self.playing then return end
	-- Queue the first beat before the engine asks for it. Opening the output
	-- can fail (no device, plugin not built); say why instead of staying silent.
	local ok, err = pcall(self.pump, self)
	if ok then ok, err = self.output:start() end
	if not ok then
		for _, refs in ipairs(self:views()) do
			refs.section.text = "Audio unavailable"
			refs.detail.text = tostring(err)
		end
		return
	end
	self:setTransport(true)
end

function Controller:stop()
	if not self.playing then return end
	self.output:pause()
	self:setTransport(false)
end

-- Skips to the next track of the set at the next bar line; its intro mixes
-- in under the current tune as it would from a DJ.
function Controller:nextTrack()
	local synth = self.synth
	local current = synth.composerBar
	if #synth.timeline > 0 then current = synth.timeline[#synth.timeline].index end
	local track = self.composer:trackAt(current)
	synth.composerBar = self.composer:trackStart(track.index + 1)
	if not self.playing then self:showIdle() end
end

-- A new seed takes over at the next bar line and starts a whole new set.
function Controller:newSet()
	self.model:reseed(self.model.seed + 1)
	self.composer = Styles:create(self.style.id, self.model.seed)
	self.synth:setComposer(self.composer)
	if not self.playing then self:showIdle() end
end

-- Picture in Picture, after the Music app's MiniPlayer: the main window
-- steps aside for a small floating window that keeps the visualizer and
-- transport. Closing it, or its restore button, brings the main window back.
function Controller:openMiniPlayer()
	if self.mini then return end
	local config, refs = xml.renderFile(VIEWS .. "MiniPlayer.etlua", {
		title = self.style.title, program = Visualizers.program(), nowPlaying = self:nowPlaying(),
		actions = self:actions(),
	})
	self:present(refs)
	self.mini = {window = ns.Window(config), refs = refs}
	self:setTransport(self.playing)
	if self.window then self.window:hide() end
end

function Controller:closeMiniPlayer()
	if self.mini then self.mini.window:close() end
end

-- The mini player's window is closing, by its restore button or its close
-- button; the main window comes back before AppKit checks for open windows.
function Controller:miniPlayerClosed()
	self.mini = nil
	if self.window then ns.showWindow(self.window) end
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", self:viewData())
	self.refs = refs
	self:present(refs)
	self.window = ns.Window(config)
	self:setTransport(false)
	-- The display loop lives as long as the window's Lua state; closing the
	-- window cancels its timer.
	self.async(function()
		while true do
			self:tick(PLAYBACK.frameInterval)
			self.sleep(PLAYBACK.frameInterval)
		end
	end)
	return self.window
end

return Controller
