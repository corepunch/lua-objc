-- Speaker output through the AudioStream native plugin. The stream opens on
-- first use so loading the app (and its headless tests) never touches the
-- audio device. Tests inject a fake with the same methods.
local App = require("App")

local AudioOutput = {}
AudioOutput.__index = AudioOutput

function AudioOutput.new(sampleRate, bufferFrames)
	return setmetatable({sampleRate = sampleRate, bufferFrames = bufferFrames}, AudioOutput)
end

function AudioOutput:stream()
	if not self.handle then
		local path = assert(package.searchpath("AudioStream", package.cpath), "AudioStream plugin is not built")
		self.native = App.loadNativePlugin(path, "AudioStream")
		self.handle = self.native.open(self.sampleRate, self.bufferFrames)
	end
	return self.handle
end

-- Returns true, or nil and the audio engine's error message.
function AudioOutput:start()
	local handle = self:stream()
	return self.native.start(handle)
end

function AudioOutput:pause()
	if self.handle then self.native.pause(self.handle) end
end

-- Frames that can be queued now.
function AudioOutput:space()
	local handle = self:stream()
	return self.native.space(handle)
end

function AudioOutput:write(samples, frames)
	local handle = self:stream()
	return self.native.write(handle, samples, frames)
end

-- Log-spaced band levels (0…1) and RMS of what the device just played.
function AudioOutput:spectrum(bands)
	local handle = self:stream()
	return self.native.spectrum(handle, bands)
end

-- Frames the device has played since the stream opened.
function AudioOutput:played()
	local handle = self:stream()
	return (self.native.played(handle))
end

return AudioOutput
