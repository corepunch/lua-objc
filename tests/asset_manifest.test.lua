-- Every shared asset kit's manifest.lua is what scripts/assets/manifest.lua
-- generates from the models now (sizes from the loader that draws them), and
-- every model it lists exists. Regenerate after adding or changing a model:
--   ./lua-objc scripts/assets/manifest.lua assets/kenney/<kit>
_G.__headless = true
local t = require("TestKit")

local kits = {}
local listing = io.popen("ls assets/kenney")
for name in listing:lines() do
	local f = io.open("assets/kenney/" .. name .. "/models", "r")
	if f then f:close(); table.insert(kits, name) end
end
listing:close()
t.expect(#kits > 0, "there is at least one shared kit")

for _, kit in ipairs(kits) do
	local root = "assets/kenney/" .. kit
	local ok = os.execute("./lua-objc scripts/assets/manifest.lua --check " .. root .. " >/dev/null 2>&1")
	t.expect(ok == true or ok == 0, kit .. "'s manifest matches its models")
	local manifest = dofile(root .. "/manifest.lua")
	local count, missing = 0, {}
	for name, entry in pairs(manifest) do
		count = count + 1
		local f = io.open(root .. "/models/" .. name .. ".glb", "rb")
		if f then f:close() else table.insert(missing, name) end
		if not (entry.size and #entry.size == 3 and entry.size[2] >= 0 and entry.pivot) then table.insert(missing, name .. " (fields)") end
	end
	t.expect(count > 0 and #missing == 0, kit .. ": every entry names a model with size and pivot " .. table.concat(missing, ", "))
	local license = io.open(root .. "/License.txt", "r")
	t.expect(license ~= nil, kit .. " carries its license")
	if license then license:close() end
end

local platformer = dofile("assets/kenney/platformer-kit/manifest.lua")
t.assertEqual(platformer["coin-gold"].pivot, "bottom center", "a coin stands on its position")
t.expect(platformer["block-grass"].size[2] == 1, "a block is one unit tall")
local clips = table.concat(platformer["character-oobi"].clips, " ")
t.expect(clips:find("walk") and platformer["character-oobi"].skinned, "characters list their clips")

os.exit(t.summary() and 0 or 1)
