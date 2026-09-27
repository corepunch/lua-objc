local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.dnb.Model")
local Composer = require("apps.dnb.models.Composer")
local Synth = require("apps.dnb.models.Synth")
local Visuals = require("apps.dnb.models.Visuals")
local AudioOutput = require("apps.dnb.services.AudioOutput")

local VIEWS = "apps/dnb/views/"

-- The queue is the latency between moving a control and hearing it. The
-- display loop refills it and animates the visualizer at about 60 Hz, which
-- leaves many refills of headroom before the device would run dry.
local PLAYBACK = {sampleRate = 44100, bufferSeconds = 0.3, frameInterval = 1 / 60}

local SECTION_TITLES = {intro = "Intro", build = "Build-up", drop = "Drop", breakdown = "Breakdown"}

local Controller = {}
Controller.__index = Controller

-- `options` lets tests inject an output, seed and scheduler.
function Controller.new(options)
	options = options or {}
	local model = Model.new(options.seed or os.time())
	local self = setmetatable({
		model = model,
		synth = Synth.new(model, PLAYBACK.sampleRate),
		output = options.output or AudioOutput.new(PLAYBACK.sampleRate,
			math.floor(PLAYBACK.sampleRate * PLAYBACK.bufferSeconds)),
		async = options.async or ns.async,
		sleep = options.sleep or ns.sleep,
		buffer = {},
		playing = false,
		visuals = Visuals.new(),
	}, Controller)
	self.composer = Composer.new(model.seed)
	self.synth:setComposer(self.composer)
	return self
end

-- Now-playing text for a bar, or for the first bar before playback starts.
function Controller:nowPlaying(bar, fraction)
	local playing = bar ~= nil
	bar = bar or self.composer:bar(0, self.model)
	return {
		section = playing and SECTION_TITLES[bar.section] or "Ready to play",
		detail = bar.key .. " · " .. bar.progression,
		position = string.format("Bar %d of %d", bar.sectionBar + 1, bar.sectionLength),
		progress = (bar.sectionBar + (fraction or 0)) / bar.sectionLength,
		tempo = self.model:formatted("tempo"):match("%d+"),
	}
end

function Controller:viewData()
	local partGroups, controlGroups = {}, {}
	for _, group in ipairs(Model.partGroups) do
		local parts = {}
		for _, part in ipairs(group.parts) do
			table.insert(parts, {id = part.id, label = part.label, on = self.model:enabled(part.id)})
		end
		table.insert(partGroups, {title = group.title, parts = parts})
	end
	for _, group in ipairs(Model.controlGroups) do
		local controls = {}
		for _, control in ipairs(group.controls) do
			table.insert(controls, {id = control.id, label = control.label, min = control.min, max = control.max,
				value = self.model:value(control.id), text = self.model:formatted(control.id)})
		end
		table.insert(controlGroups, {title = group.title, controls = controls})
	end
	return {
		nowPlaying = self:nowPlaying(),
		partGroups = partGroups,
		controlGroups = controlGroups,
		actions = self:actions(),
	}
end

function Controller:actions()
	local actions = {
		play = function() self:play() end,
		stop = function() self:stop() end,
		newTrack = function() self:newTrack() end,
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

function Controller:setControl(id, value)
	self.model:setValue(id, value)
	local label = self.refs and self.refs["value_" .. id]
	if label then label.text = self.model:formatted(id) end
	if id == "tempo" and self.refs then self.refs.tempo.text = self.model:formatted(id):match("%d+") end
end

-- Tops the output queue up with freshly synthesized audio.
function Controller:pump()
	local frames = self.output:space()
	if frames <= 0 then return 0 end
	self.synth:render(self.buffer, frames)
	self.output:write(self.buffer, frames)
	return frames
end

-- One display frame: refill audio while playing, then follow the playhead
-- in the header and the visualizer.
function Controller:tick(dt)
	if self.playing then self:pump() end
	local played = self.playing and self.output:played() or nil
	local bar = played and self.synth:barAt(played)
	if bar then self:showPlayhead(bar, played) end
	if not self.playing and self.visuals:settled() then return end
	local bands, rms
	if self.playing then bands, rms = self.output:spectrum(Visuals.bands) end
	local values = self.visuals:update({bands = bands, rms = rms, playing = self.playing, bar = bar,
		played = played, sampleRate = PLAYBACK.sampleRate, gain = self.model:value("volume")}, dt)
	if self.refs then self.refs.visualizer.values = values end
end

function Controller:showPlayhead(bar, played)
	if not self.refs then return end
	local info = self:nowPlaying(bar, math.max(0, math.min(1, (played - bar.frame) / bar.frames)))
	local refs = self.refs
	if refs.section.text ~= info.section then refs.section.text = info.section end
	if refs.detail.text ~= info.detail then refs.detail.text = info.detail end
	if refs.position.text ~= info.position then refs.position.text = info.position end
	refs.progress.doubleValue = info.progress
end

function Controller:setTransport(playing)
	self.playing = playing
	if not self.refs then return end
	self.refs.play.enabled = not playing
	self.refs.stop.enabled = playing
end

function Controller:play()
	if self.playing then return end
	-- Queue the first beat before the engine asks for it. Opening the output
	-- can fail (no device, plugin not built); say why instead of staying silent.
	local ok, err = pcall(self.pump, self)
	if ok then ok, err = self.output:start() end
	if not ok then
		if self.refs then
			self.refs.section.text = "Audio unavailable"
			self.refs.detail.text = tostring(err)
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

-- A new seed takes over at the next bar line and starts its own intro.
function Controller:newTrack()
	self.model:reseed(self.model.seed + 1)
	self.composer = Composer.new(self.model.seed)
	self.synth:setComposer(self.composer)
	if not self.playing and self.refs then
		local info = self:nowPlaying()
		self.refs.detail.text = info.detail
	end
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", self:viewData())
	self.refs = refs
	refs.visualizer.values = self.visuals:pack()
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
