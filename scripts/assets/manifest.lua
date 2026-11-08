-- Writes assets/kenney/<kit>/manifest.lua: what every model in a kit is, in
-- numbers an agent (or a person) can place pieces with, without opening a
-- model file. It is generated, never hand-written: each model is loaded by
-- the same reader that draws it in a game (src/shared/scene_gltf.m), so the
-- sizes here are the sizes on screen.
--
--   ./lua-objc scripts/assets/manifest.lua assets/kenney/platformer-kit
--   ./lua-objc scripts/assets/manifest.lua --check assets/kenney/platformer-kit
--
-- --check exits 1 when the file on disk differs from what would be written
-- (tests/asset_manifest.test.lua runs it for every kit).
_G.__headless = true
local xml = require("ui.xml")
local bridge = require("AppKitNative")

local args = {...}
if #args == 0 and arg then args = {table.unpack(arg)} end
local check = args[1] == "--check"
local kit = check and args[2] or args[1]
assert(kit, "usage: manifest.lua [--check] assets/kenney/<kit>")
kit = kit:gsub("/$", "")

-- Tags from Kenney's model names, which follow one vocabulary across kits.
-- Ordered: a name collects every tag whose pattern it contains.
local TAGS = {
	{"^block%-", "ground"}, {"^floor", "ground"}, {"^ground", "ground"}, {"^tile", "ground"},
	{"slope", "ramp"}, {"ramp", "ramp"}, {"stairs", "ramp"},
	{"overhang", "overhang"},
	{"platform", "platform"}, {"bridge", "platform"}, {"ladder", "climb"},
	{"spike", "hazard"}, {"saw", "hazard"}, {"trap", "hazard"}, {"bomb", "hazard"}, {"lava", "hazard"},
	{"coin", "pickup"}, {"heart", "pickup"}, {"star", "pickup"}, {"key", "pickup"}, {"jewel", "pickup"},
	{"gem", "pickup"}, {"chest", "container"}, {"barrel", "container"}, {"crate", "container"},
	{"door", "gate"}, {"gate", "gate"}, {"lock", "gate"},
	{"flag", "goal"},
	{"spring", "bouncer"}, {"lever", "switch"}, {"button", "switch"},
	{"character", "character"},
	{"tree", "nature"}, {"flower", "nature"}, {"grass", "nature"}, {"plant", "nature"}, {"mushroom", "nature"},
	{"rock", "nature"}, {"stone", "nature"}, {"bush", "nature"},
	{"fence", "boundary"}, {"wall", "boundary"}, {"barrier", "boundary"},
	{"sign", "decor"}, {"arrow", "decor"}, {"poles", "decor"},
	-- Racing, Car and Space kits.
	{"road", "track"}, {"monorail_track", "track"}, {"terrain", "ground"},
	{"racecar", "vehicle"}, {"^race", "vehicle"}, {"^kart", "vehicle"}, {"craft_", "vehicle"}, {"rover", "vehicle"},
	{"monorail_train", "vehicle"}, {"ambulance", "vehicle"}, {"truck", "vehicle"}, {"^van", "vehicle"}, {"taxi", "vehicle"},
	{"police", "vehicle"}, {"sedan", "vehicle"}, {"^suv", "vehicle"}, {"tractor", "vehicle"}, {"hatchback", "vehicle"},
	{"^delivery", "vehicle"},
	{"wheel", "part"}, {"debris", "debris"}, {"rocket_", "part"},
	{"grandstand", "building"}, {"pits", "building"}, {"tent", "building"}, {"hangar", "building"}, {"corridor", "building"},
	{"structure", "building"}, {"^rail", "boundary"}, {"cone", "obstacle"}, {"pylon", "obstacle"}, {"^box", "obstacle"},
	{"meteor", "hazard"}, {"turret", "hazard"}, {"weapon", "pickup"}, {"alien", "character"}, {"astronaut", "character"},
	{"crater", "nature"}, {"^overhead", "overhead"}, {"light", "decor"}, {"banner", "decor"}, {"billboard", "decor"}, {"pipe", "pipe"},
	{"%-snow", "snow"}, {"%-grass", "grass"},
	{"%-large", "large"}, {"%-low", "low"}, {"%-narrow", "narrow"}, {"%-long", "long"}, {"%-small", "small"},
}

local function tags(name)
	name = name:lower() -- older kits name models in camelCase
	local out, seen = {}, {}
	for _, rule in ipairs(TAGS) do
		if name:find(rule[1]) and not seen[rule[2]] then seen[rule[2]] = true; table.insert(out, rule[2]) end
	end
	-- "grass" is both a biome (block-grass-*) and a plant (grass.glb).
	if seen.grass and seen.nature and name:find("^block") then
		for i, tag in ipairs(out) do if tag == "nature" then table.remove(out, i) break end end
	end
	return out
end

local function round(n) return math.floor(n * 1000 + 0.5) / 1000 end

-- Where the model's origin sits in its bounds: what `position` means.
local function pivot(n)
	local function axis(low, high)
		local size = high - low
		if size < 1e-6 then return "center" end
		local at = -low / size
		if math.abs(at) < 0.02 then return "min" elseif math.abs(at - 1) < 0.02 then return "max"
		elseif math.abs(at - 0.5) < 0.02 then return "center" end
		return string.format("%.2f", at)
	end
	local y = axis(n.bottom, n.maxY)
	return (y == "min" and "bottom" or y == "max" and "top" or y == "center" and "middle" or ("y " .. y)) .. " "
		.. (axis(n.minX, n.maxX) == "center" and axis(n.minZ, n.maxZ) == "center" and "center"
			or ("x " .. axis(n.minX, n.maxX) .. ", z " .. axis(n.minZ, n.maxZ)))
end

local models = {}
local listing = io.popen('ls "' .. kit .. '/models"')
for file in listing:lines() do
	local name = file:match("^(.-)%.glb$")
	if name then table.insert(models, name) end
end
listing:close()
table.sort(models)
assert(#models > 0, kit .. "/models has no .glb files")

local body = {}
for _, name in ipairs(models) do
	local path = kit .. "/models/" .. name .. ".glb"
	local _, refs = xml.render('<SceneView id="s"><Node id="m" model="' .. path .. '" /></SceneView>', {})
	local n = bridge._sceneNodes(refs.s).m
	local entry = {
		string.format('\t["%s"] = {', name),
		string.format('\t\tsize = {%s, %s, %s}, -- width (x), height (y), depth (z)', round(n.width), round(n.height), round(n.length)),
		string.format('\t\tbounds = {%s, %s, %s, %s, %s, %s}, -- min x y z, max x y z',
			round(n.minX), round(n.bottom), round(n.minZ), round(n.maxX), round(n.maxY), round(n.maxZ)),
		string.format('\t\tpivot = "%s",', pivot(n)),
	}
	local tagList = tags(name)
	if #tagList > 0 then table.insert(entry, string.format('\t\ttags = {"%s"},', table.concat(tagList, '", "'))) end
	if n.clips and #n.clips > 0 then table.insert(entry, string.format('\t\tclips = {"%s"},', table.concat(n.clips, '", "'))) end
	if n.skinned then table.insert(entry, "\t\tskinned = true,") end
	table.insert(entry, "\t},")
	table.insert(body, table.concat(entry, "\n"))
end

local kitName = kit:match("([^/]+)$")
local text = table.concat({
	"-- " .. kitName .. ": every model in models/, generated by",
	"-- scripts/assets/manifest.lua from the loader that draws them. Do not edit.",
	"--",
	"-- Units are scene units (metres). `pivot` says where the model's origin",
	"-- sits: \"bottom center\" stands on `position`, centred on it; a number is",
	"-- the origin's place along that axis, 0 at the min edge and 1 at the max",
	"-- (\"z 0.48\" is near the middle). `tags` come from",
	"-- the model's name; `clips` are animations `<Node animation=\"...\">` plays.",
	"-- Use as: Node model=\"" .. kit .. "/models/<name>.glb\"",
	"return {",
	table.concat(body, "\n"),
	"}",
	"",
}, "\n")

local target = kit .. "/manifest.lua"
if check then
	local file = io.open(target, "r")
	local current = file and file:read("a")
	if file then file:close() end
	if current ~= text then
		io.stderr:write(target .. " is out of date: run ./lua-objc scripts/assets/manifest.lua " .. kit .. "\n")
		os.exit(1)
	end
	os.exit(0)
end
local file = assert(io.open(target, "w"))
file:write(text)
file:close()
print(string.format("%s: %d models", target, #models))
os.exit(0)
