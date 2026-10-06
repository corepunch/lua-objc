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

function Audio:play(path, from, to) return self:plugin().play(path, from, to) end

function Audio:stop() if self.native then self.native.stop() end end

return Audio
