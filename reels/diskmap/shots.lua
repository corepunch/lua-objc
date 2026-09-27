-- Bespoke shots: drawn with the pen where the element vocabulary would only
-- get in the way. Each is shots.name(pen, t, node), placed by its <Draw>.
local Curves = require("reel.curves")

local progress, mix, spring, pulse, clamp01 = Curves.progress, Curves.mix, Curves.spring, Curves.pulse, Curves.clamp01
local inOutExpo, inOutCubic = Curves.easing.inOutExpo, Curves.easing.inOutCubic

local shots = {}

-- 24–26 s: twelve pages spring onto a wall that pans, then the camera dives
-- into the Map page's sunburst. The dive keeps the sunburst's centre fixed
-- on screen while zooming 16×, swapping in the full-resolution page once it
-- is large.
local WALL = { columns = 4, rows = 3, cellWidth = 600, cellHeight = 390, scale = 0.37, target = 6,
	start = 23.95, ripple = 0.35, rippleDistance = 1500, zoom = 16, tilt = -0.16, swapZoom = 2.2 }

function shots.wall(pen, t, node)
	local data, captures = node.context.data, node.context.captures
	local pages = data.wallPages
	local function cellCenter(i)
		local index = i - 1
		return (index % WALL.columns - (WALL.columns - 1) / 2) * WALL.cellWidth,
			(index // WALL.columns - (WALL.rows - 1) / 2) * WALL.cellHeight
	end
	local target = captures:get(pages[WALL.target])
	local sx, sy, sw, sh = target:rect("#sunburst")
	local ww, wh = target:size()
	local tx, ty = cellCenter(WALL.target)
	local sunX, sunY = tx + (sx + sw / 2 - ww / 2) * WALL.scale, ty + (sy + sh / 2 - wh / 2) * WALL.scale
	local dive = inOutExpo(progress(t, 25.3, 26.0))
	local pan = mix(420, -380, inOutCubic(progress(t, 23.9, 25.5)))
	local fx, fy = mix(pan, sunX, dive), mix(0, sunY, dive)
	local zoom = math.exp(mix(0, math.log(WALL.zoom), dive)) * (1 + 0.02 * pulse(t, data.kicks, 0.14))
	local rotation = mix(WALL.tilt, 0, dive)
	local c, s = math.cos(rotation), math.sin(rotation)
	for i, name in ipairs(pages) do
		local cx, cy = cellCenter(i)
		local delay = WALL.start + math.sqrt(cx * cx + cy * cy) / WALL.rippleDistance * WALL.ripple
		local vx, vy = (cx - fx) * zoom, (cy - fy) * zoom
		local x, y = 960 + vx * c - vy * s, 540 + vx * s + vy * c
		local scale = WALL.scale * zoom * spring(t - delay, 1 / 2.0, 0.55)
		local offscreen = math.abs(x - 960) > ww * scale / 2 + 1100 or math.abs(y - 540) > wh * scale / 2 + 800
		if not offscreen then
			local capture = captures:get(name)
			local sprite = (i == WALL.target and zoom > WALL.swapZoom) and capture:piece("window")
				or capture:piece("window", { downsample = 0.3 })
			pen:place({ x = x, y = y, scale = scale, rotation = rotation, alpha = clamp01((t - delay) / 0.1),
				anchor = { ww / 2, wh / 2 } }, function()
				pen:sprite(sprite, { radius = 24, shadow = 0.8 })
			end)
		end
	end
	local flash = progress(t, 25.82, 26.0)
	if flash > 0 then pen:rect(0, 0, 1920, 1080, { 0, 0, 0, flash }) end
end

return shots
