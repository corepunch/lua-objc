-- Diskmap's Mac App Store screenshots (apps/diskmap/store-assets/en/screenshots,
-- made by `make diskmap-store-screenshots`): App Store Connect accepts only
-- four sizes and no transparency, so every file is a JPEG of one of them.
_G.__headless = true
local t = require("TestKit")

local DIR = "apps/diskmap/store-assets/en/screenshots/"
local SIZES = { ["1280x800"] = true, ["1440x900"] = true, ["2560x1600"] = true, ["2880x1800"] = true }

-- The frame size from a JPEG's start-of-frame marker.
local function jpegSize(path)
	local file = assert(io.open(path, "rb"))
	local data = file:read("a")
	file:close()
	if data:sub(1, 2) ~= "\255\216" then return nil end
	local at = 3
	while at < #data do
		local marker, length = data:byte(at + 1), data:byte(at + 2) * 256 + data:byte(at + 3)
		if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
			local h = data:byte(at + 5) * 256 + data:byte(at + 6)
			local w = data:byte(at + 7) * 256 + data:byte(at + 8)
			return w, h
		end
		at = at + 2 + length
	end
end

local shots = {}
for name in io.popen('ls "' .. DIR .. '"'):lines() do table.insert(shots, name) end
t.expect(#shots >= 1 and #shots <= 10, "the listing has between one and ten screenshots")
for _, name in ipairs(shots) do
	t.expect(name:match("^%d%d%-[%w-]+%.jpg$") ~= nil, name .. " is a numbered JPEG (no transparency)")
	local w, h = jpegSize(DIR .. name)
	t.expect(w and SIZES[w .. "x" .. h], string.format("%s is an accepted Mac size (%sx%s)", name, tostring(w), tostring(h)))
end

os.exit(t.summary() and 0 or 1)
