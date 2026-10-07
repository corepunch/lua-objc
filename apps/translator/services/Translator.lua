-- The offline English→Russian engine: the en-ru-translator submodule (a
-- Lua port of the 1992 LTGOLD rule-based translator) run in-process.
--
-- The submodule is a plain Lua project that requires its modules from its
-- own root (`core.engine`) and opens its assets with io.open. On
-- iOS the host's files are streamed or bundled, not on disk, so each call
-- into the engine runs with the submodule root on package.path and io.open
-- reading through `ns._readFile`, as Adventure Arena runs zilscript
-- (services/ZILRuntime.lua). The static executable tables and dictionaries
-- load on the first nonempty input, not at launch. The executable is read
-- as data; all translation runs in Lua.
local ROOT = "apps/translator/en-ru-translator"
local DATA = "apps/translator/data"

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
		-- The engine also probes raw asset bytes with io.open. Let the
		-- ordinary reader reject embedded NULs before reaching platform IO.
		if path:find("\0", 1, true) then return fallback(path, mode) end
		if path:sub(1, 1) == "/" or (mode and mode:find("[wa+]")) then return fallback(path, mode) end
		local body, err = readFile(path)
		if not body then return nil, err end
		return fileOver(body)
	end
end

-- `options.readFile` replaces the platform's reader (nil on AppKit, where
-- the files are on disk); `options.root` the submodule folder and
-- `options.dataRoot` the original engine assets bundled with the app.
function Translator.new(options)
	options = options or {}
	local readFile = options.readFile
	if readFile == nil then
		local ok, ns = pcall(require, "ns")
		readFile = ok and type(ns) == "table" and ns._readFile or nil
	end
	return setmetatable({ root = options.root or ROOT, dataRoot = options.dataRoot or DATA,
		readFile = readFile }, Translator)
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
	local engine, assets = self:within(function()
		local module = require("core.engine")
		return module, {
			executable = module.read_asset(self.dataRoot .. "/LTPRO.EXE", "LTPRO.EXE"),
			dictionary = module.read_asset(self.dataRoot .. "/BASE.DIC", "BASE.DIC"),
			russian = module.read_asset(self.dataRoot .. "/BASE.RUS", "BASE.RUS"),
		}
	end)
	self.engine, self.assets = engine, assets
	return self.engine
end

-- The engine reads one sentence run at a time and drops line breaks, so
-- each line is translated alone and the lines are joined again. The page
-- translates on every keystroke; lines are remembered from the previous
-- call, so a keystroke translates only the line it changed. Returns the
-- Russian text, or nil and the engine's message.
function Translator:translate(text)
	text = tostring(text or "")
	if not text:match("%S") then self.lines = {}; return "" end
	local previous, current = self.lines or {}, {}
	local ok, result = pcall(self.within, self, function()
		local engine = self:load()
		local lines = {}
		for line in (text .. "\n"):gmatch("(.-)\r?\n") do
			local english = line:match("^%s*(.-)%s*$")
			if english ~= "" then
				local russian = current[english] or previous[english]
				if not russian then
					russian = engine.translate(english, self.assets)
				end
				current[english] = russian
				table.insert(lines, russian)
			else
				table.insert(lines, "")
			end
		end
		return (table.concat(lines, "\n"):gsub("%s+$", ""))
	end)
	if not ok then return nil, tostring(result) end
	self.lines = current
	return result
end

return Translator
