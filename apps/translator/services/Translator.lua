-- In-process offline translation. Both desktop files and the iPhone reader
-- load the same language data from the engine submodule.
local ROOT = "apps/translator/en-ru-translator"
local Translator = {}
Translator.__index = Translator

function Translator.new(options)
	options = options or {}
	local readFile = options.readFile
	if readFile == nil then
		local ok, ns = pcall(require, "ns")
		readFile = ok and type(ns) == "table" and ns._readFile or nil
	end
	local root = options.root or ROOT
	return setmetatable({ root = root, dataRoot = options.dataRoot or root .. "/dictionary",
		readFile = readFile }, Translator)
end

function Translator:isLoaded() return self.engine ~= nil end

function Translator:load()
	if self.engine then return self.engine end
	local originalPath = package.path
	package.path = self.root .. "/?.lua;" .. originalPath
	local ok, engine = pcall(require, "en_ru.engine")
	package.path = originalPath
	if not ok then error(engine, 0) end
	local lexicon = engine.load({ data_dir = self.dataRoot, read_file = self.readFile or nil })
	self.options = { lexicon = lexicon, formal = true }
	self.engine = engine
	return engine
end

-- Keep unchanged editor lines across keystrokes, including blank lines.
function Translator:translate(text)
	text = tostring(text or "")
	if not text:match("%S") then self.lines = {}; return "" end
	local previous, current = self.lines or {}, {}
	local ok, result = pcall(function()
		local engine = self:load()
		local lines = {}
		for line in (text .. "\n"):gmatch("(.-)\r?\n") do
			local english = line:match("^%s*(.-)%s*$")
			if english ~= "" then
				local russian = current[english] or previous[english]
				if not russian then russian = engine.translate(english, self.options) end
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
