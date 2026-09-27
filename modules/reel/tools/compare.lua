-- ./lua-objc modules/reel/tools/compare.lua <a.mov> <b.mov> <out.mov> [label a] [label b]
--
-- A side-by-side comparison movie of two renders of the same length and
-- size, with their difference below (amplified 4×), and a report of how far
-- each frame differs: mean and largest channel difference in 0…255 on a
-- 192×108 sample. The sound is taken from <a.mov>.
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")

local pathA, pathB, output = arg[1], arg[2], arg[3]
if not (pathA and pathB and output) then
	io.stderr:write("usage: compare.lua <a.mov> <b.mov> <out.mov> [label a] [label b]\n")
	os.exit(1)
end
local labelA, labelB = arg[4] or pathA:match("[^/]+$"), arg[5] or pathB:match("[^/]+$")

local N = Reel.native()
local W, H = 1920, 1080
local LAYOUT = { top = 96, tile = { w = 944, h = 531 }, gutter = 16, diff = { w = 560, h = 315 }, sample = { w = 192, h = 108 } }
local SAMPLE_STEP = 2

local canvas = N.canvas(W, H)
local pen = Reel.Pen.new(canvas, N)
local label = Reel.Pen.style(30, "semibold", 0xF5F5F7, 0)
local caption = Reel.Pen.style(24, "regular", 0x98989D, 0)
local diffCanvas = N.canvas(LAYOUT.diff.w, LAYOUT.diff.h)
local sampleA, sampleB = N.canvas(LAYOUT.sample.w, LAYOUT.sample.h), N.canvas(LAYOUT.sample.w, LAYOUT.sample.h)
local movie = N.movie({ path = output, width = W, height = H, fps = 30, audio = pathA })
local framesA, framesB = N.frames(pathA), N.frames(pathB)

local function measure(a, b)
	sampleA:image(a, 0, 0, LAYOUT.sample.w, LAYOUT.sample.h)
	sampleB:image(b, 0, 0, LAYOUT.sample.w, LAYOUT.sample.h)
	local sum, worst, count = 0, 0, 0
	for y = 0, LAYOUT.sample.h - 1, SAMPLE_STEP do
		for x = 0, LAYOUT.sample.w - 1, SAMPLE_STEP do
			local r1, g1, b1 = sampleA:pixel(x, y)
			local r2, g2, b2 = sampleB:pixel(x, y)
			local d = (math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)) / 3 * 255
			sum, count = sum + d, count + 1
			if d > worst then worst = d end
		end
	end
	return sum / count, worst
end

local stats, frame = {}, 0
while true do
	local a, b = framesA:next(), framesB:next()
	if not a or not b then break end
	frame = frame + 1
	local mean, worst = measure(a, b)
	table.insert(stats, { mean = mean, worst = worst })
	canvas:clear(0.03, 0.03, 0.04, 1)
	local xA, xB = (W - LAYOUT.tile.w * 2 - LAYOUT.gutter) / 2, (W + LAYOUT.gutter) / 2
	canvas:image(a, xA, LAYOUT.top, LAYOUT.tile.w, LAYOUT.tile.h)
	canvas:image(b, xB, LAYOUT.top, LAYOUT.tile.w, LAYOUT.tile.h)
	pen:text(labelA, label, xA, LAYOUT.top - 24, "leading")
	pen:text(labelB, label, xB, LAYOUT.top - 24, "leading")
	-- The difference, amplified by adding it to itself.
	diffCanvas:clear(0, 0, 0, 1)
	diffCanvas:image(a, 0, 0, LAYOUT.diff.w, LAYOUT.diff.h)
	diffCanvas:blend("difference")
	diffCanvas:image(b, 0, 0, LAYOUT.diff.w, LAYOUT.diff.h)
	diffCanvas:blend("normal")
	local diff = diffCanvas:snapshot()
	local dx, dy = (W - LAYOUT.diff.w) / 2, LAYOUT.top + LAYOUT.tile.h + 64
	canvas:blend("plusLighter")
	for _ = 1, 4 do canvas:image(diff, dx, dy, LAYOUT.diff.w, LAYOUT.diff.h) end
	canvas:blend("normal")
	pen:text("Difference × 4", label, dx, dy - 16, "leading")
	pen:text(string.format("%.2fs   mean %.2f / 255   largest %.0f / 255", (frame - 1) / 30, mean, worst),
		caption, W / 2, dy + LAYOUT.diff.h + 40, "center")
	movie:append(canvas)
	if frame % 90 == 0 then io.write(string.format("frame %d\n", frame)); io.flush() end
end
movie:finish()

local total, peak, over = 0, { mean = 0 }, 0
for i, s in ipairs(stats) do
	total = total + s.mean
	if s.mean > peak.mean then peak = { mean = s.mean, frame = i } end
	if s.mean > 2 then over = over + 1 end
end
print(string.format("%d frames compared: mean difference %.2f / 255; worst frame %d (%.2fs) at %.2f / 255; %d frames above 2 / 255",
	#stats, total / #stats, peak.frame or 0, ((peak.frame or 1) - 1) / 30, peak.mean, over))
local seconds = {}
for i, s in ipairs(stats) do
	local second = (i - 1) // 30 + 1
	seconds[second] = math.max(seconds[second] or 0, s.mean)
end
local line = {}
for second, value in ipairs(seconds) do table.insert(line, string.format("%d:%.1f", second - 1, value)) end
print("worst mean per second: " .. table.concat(line, " "))
local above = {}
for i, s in ipairs(stats) do if s.mean > 2 then table.insert(above, string.format("%.2fs", (i - 1) / 30)) end end
if #above > 0 then print("above 2 / 255: " .. table.concat(above, " ")) end
os.exit(0)
