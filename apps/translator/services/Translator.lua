-- The offline English→Russian engine: the en-ru-translator submodule (a
-- Lua port of the 1992 LTGOLD rule-based translator) run in-process.
--
-- The submodule is a plain Lua project that requires its modules from its
-- own root (`core.translator`) and opens its dictionaries with io.open. On
-- iOS the host's files are streamed or bundled, not on disk, so each call
-- into the engine runs with the submodule root on package.path and io.open
-- reading through `ns._readFile`, as Adventure Arena runs zilscript
-- (services/ZILRuntime.lua). The dictionaries (2 MB) load on the first
-- keystroke, not at launch.
local ROOT = "apps/translator/en-ru-translator"

local Translator = {}
Translator.__index = Translator

-- A read-only file over `body` with the methods the engine calls.
local function fileOver(body)
	return {
		lines = function()
			if body:sub(-1) ~= "\n" then body = body .. "\n" end
			return body:gmatch("(.-)\r?\n")
		end,
		read = function() return body end,
		close = function() end,
	}
end

local function readerOpen(readFile, fallback)
	if not readFile then return fallback end
	return function(path, mode)
		if path:sub(1, 1) == "/" or (mode and mode:find("[wa+]")) then return fallback(path, mode) end
		local body, err = readFile(path)
		if not body then return nil, err end
		return fileOver(body)
	end
end

-- `options.readFile` replaces the platform's reader (nil on AppKit, where
-- the files are on disk); `options.root` the submodule folder.
function Translator.new(options)
	options = options or {}
	local readFile = options.readFile
	if readFile == nil then
		local ok, ns = pcall(require, "ns")
		readFile = ok and type(ns) == "table" and ns._readFile or nil
	end
	return setmetatable({ root = options.root or ROOT, readFile = readFile }, Translator)
end

function Translator:within(operation, ...)
	local originalOpen, originalPath = io.open, package.path
	io.open = readerOpen(self.readFile, originalOpen)
	package.path = self.root .. "/?.lua;" .. originalPath
	local result = table.pack(pcall(operation, ...))
	io.open, package.path = originalOpen, originalPath
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end

function Translator:isLoaded() return self.engine ~= nil end

function Translator:load()
	if self.engine then return self.engine end
	self.engine = self:within(function()
		local store = require("dictionary_store")
		local english, russian = store.load(self.root .. "/data/BASE.DIC", self.root .. "/data/BASE.RUS")
		return require("core.translator").new(english, russian)
	end)
	return self.engine
end

-- The engine reads one sentence run at a time and drops line breaks, so
-- each line is translated alone and the lines are joined again. The page
-- translates on every keystroke; lines are remembered from the previous
-- call, so a keystroke costs the one line it changed (10-50 ms), not the
-- whole text. Returns the Russian text, or nil and the engine's message.
function Translator:translate(text)
	local engine = self:load()
	local previous, current = self.lines or {}, {}
	local result, err = self:within(function()
		local lines = {}
		for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
			local english = line:match("^%s*(.-)%s*$")
			if english ~= "" then
				local russian = current[english] or previous[english]
				if not russian then
					local message
					russian, message = engine:translate(english)
					if not russian then return nil, message end
				end
				current[english] = russian
				table.insert(lines, russian)
			else
				table.insert(lines, "")
			end
		end
		return (table.concat(lines, "\n"):gsub("%s+$", ""))
	end)
	self.lines = current
	return result, err
end

return Translator
