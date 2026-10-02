_G.__headless = true
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Blocks = require("apps.dnb.host.Blocks")

-- The block files the generator ships: the shared set and each style's.
local GENRES = {"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"}
local QUOTA = {drums = 12, tops = 5, bass = 12, pad = 4, keys = 4, stab = 5, arp = 6, lead = 10, counter = 4,
	texture = 4, fx = 8}
-- Genres that write no risers: the arranger then has none to place.
local NO_RISERS = {techno = true, breakbeat = true}

local ok, common = pcall(require, "apps.dnb.library.blocks.common")
t.expect(ok, "the shared blocks load: " .. tostring(common))
local lists = {ok and common or {}}
local byGenre = {}
for _, genre in ipairs(GENRES) do
	local loaded, list = pcall(require, "apps.dnb.plugins.styles." .. genre .. ".blocks")
	t.expect(loaded, genre .. " blocks load: " .. tostring(list))
	byGenre[genre] = loaded and list or {}
	table.insert(lists, byGenre[genre])
end

-- Each file is parsed alone first, so one broken block names its file.
local good = {}
for index, list in ipairs(lists) do
	local name = index == 1 and "common" or GENRES[index - 1]
	local parsed, err = pcall(Blocks.catalogue, {list})
	t.expect(parsed, name .. " blocks parse: " .. tostring(err))
	if parsed then table.insert(good, list) end
end
local catalogue = Blocks.catalogue(good)
t.expect(#catalogue.list > 400, "the library holds " .. #catalogue.list .. " blocks")

for _, genre in ipairs(GENRES) do
	local counts, energies, mixable, halftime, risers, impacts, down = {}, {}, 0, 0, 0, 0, 0
	for _, block in ipairs(byGenre[genre]) do
		local parsed = catalogue.byId[block.id]
		if not parsed then break end
		t.assertEqual(parsed.genre, genre, block.id .. " is in its own genre's file")
		counts[parsed.role] = (counts[parsed.role] or 0) + 1
		energies[parsed.role] = energies[parsed.role] or {}
		table.insert(energies[parsed.role], parsed.energy)
		if parsed.role == "drums" and parsed.tags.mixable and parsed.energy < 0.5 then mixable = mixable + 1 end
		if parsed.role == "drums" and parsed.tags.halftime then halftime = halftime + 1 end
		if parsed.kind == "riser" then risers = risers + 1 end
		if parsed.kind == "impact" then impacts = impacts + 1 end
		if parsed.kind == "downlifter" then down = down + 1 end
	end
	for role, quota in pairs(QUOTA) do
		if not (NO_RISERS[genre] and role == "fx") then
			t.expect((counts[role] or 0) >= quota, genre .. " has " .. (counts[role] or 0) .. " " .. role .. " blocks, needs " .. quota)
		end
		-- A role needs its whole range of energy to be quiet and to be loud.
		local list = energies[role]
		if list and #list >= 4 and role ~= "fx" and role ~= "texture" then
			table.sort(list)
			t.expect(list[1] <= 0.5 and list[#list] >= 0.7,
				string.format("%s %s spans energy (%.2f to %.2f)", genre, role, list[1], list[#list]))
		end
	end
	t.expect(mixable >= 4, genre .. " has " .. mixable .. " quiet mixable drums, needs 4")
	if genre == "dnb" or genre == "dubstep" then
		t.expect(halftime >= 2, genre .. " has halftime drums")
	end
	if not NO_RISERS[genre] then
		t.expect(risers >= 2 and impacts >= 2 and down >= 1, genre .. " has risers, impacts and a downlifter")
	end
end

-- Every role is one the channels know.
for _, block in ipairs(catalogue.list) do
	t.expect(Model.family[block.role] ~= nil, block.id .. " plays a real role")
end

os.exit(t.summary() and 0 or 1)
