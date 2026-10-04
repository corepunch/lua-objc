-- The Diskmap showreel's storyboard (reels/diskmap/views): every line of
-- type stays on screen at least a second after its last word has landed,
-- and the reel speaks to everyone, not only developers. Reads the templates
-- as text; captures are generated and not needed.
_G.__headless = true
package.path = "modules/reel/?.lua;" .. package.path

local t = require("TestKit")
local Reel = require("Reel")
local Text = Reel.elements.Text

local VIEWS = "reels/diskmap/views/"
local READ = 1.0 -- seconds a landed line holds before it leaves

local function read(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("a")
	file:close()
	return source
end

local views = {}
for name in io.popen('ls "' .. VIEWS .. '"'):lines() do
	if name:match("%.etlua$") then views[name] = read(VIEWS .. name) end
end
t.expect(views["Reel.etlua"] and views["Map.etlua"], "the storyboard templates are found")

local lines = 0
for name, source in pairs(views) do
	for tag in source:gmatch("<Text%s.-/>") do
		local text = tag:match('text="([^"]*)"')
		local at, exit = tonumber(tag:match('%sat="([%d.]+)"')), tonumber(tag:match('%sexit="([%d.]+)"'))
		local stagger = tonumber(tag:match('%sstagger="([%d.]+)"'))
		if exit then
			lines = lines + 1
			local words = 0
			for _ in text:gmatch("%S+") do words = words + 1 end
			local landed = Text.landing(at, words, stagger)
			t.expect(exit - landed >= READ - 1e-9, string.format("%s: \"%s\" holds %.2f s after landing (needs %.1f)",
				name, text, exit - landed, READ))
		end
	end
	t.expect(not source:find("[Dd]evelopers"), name .. " does not single out developers")
end
t.expect(lines >= 10, "the storyboard's timed lines are all checked")
t.expect(not views["Developers.etlua"] and not views["Simulators.etlua"], "the developer scenes are gone")

-- The four words of the opening slam hold for a second before they squash.
local intro = views["Intro.etlua"]
local hits = intro:match('<Slam[^>]-at="([^"]+)"')
local last = 0
for hit in hits:gmatch("[%d.]+") do last = math.max(last, tonumber(hit)) end
local squash = tonumber(intro:match('sx="1 %+ inQuart%(progress%(t, ([%d.]+)'))
t.expect(squash - Reel.elements.Slam.landing(last) >= READ, "the opening slam holds before it squashes")

-- A word lands once its spring settles: later than it starts, sooner than a second.
local landing = Text.landing(0, 1)
t.expect(landing > 0.2 and landing < 1, "a word settles within a second of starting")
t.expect(math.abs(Text.landing(1, 3, 0.1) - Text.landing(1, 1) - 0.2) < 1e-9, "each further word lands one stagger later")

os.exit(t.summary() and 0 or 1)
