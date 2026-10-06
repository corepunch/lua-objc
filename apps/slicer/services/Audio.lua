-- Sound files through the AudioFile native plugin: reading a file's length,
-- writing slices and auditioning them. The plugin loads on first use, so
-- loading the app never touches it; tests inject a fake with these methods.
local App = require("App")

local Audio = {}
Audio.__index = Audio

function Audio.new()
	return setmetatable({}, Audio)
end

function Audio:plugin()
	if not self.native then
		local path = assert(package.searchpath("AudioFile", package.cpath), "AudioFile plugin is not built")
		self.native = App.loadNativePlugin(path, "AudioFile")
	end
	return self.native
end

-- {duration, frames, sampleRate, channels}, or nil and a message.
function Audio:info(path) return self:plugin().info(path) end

-- Writes seconds `from`…`to` of `path` to `out` as WAV; frames written, or
-- nil and a message.
function Audio:export(path, from, to, out) return self:plugin().export(path, from, to, out) end

-- `onEnd()` runs once the span has been heard, not after `stop`.
function Audio:play(path, from, to, onEnd) return self:plugin().play(path, from, to, onEnd) end

function Audio:pause() if self.native then self.native.pause() end end

function Audio:resume() if self.native then self.native.resume() end end

function Audio:stop() if self.native then self.native.stop() end end

return Audio
