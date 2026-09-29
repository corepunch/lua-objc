-- The photo studio the devices stand in, as an equirectangular lighting
-- environment drawn with the reel's own pen: a near-black room with a large
-- soft key overhead, two tall strip lights and a faint warm floor bounce.
-- SceneKit lights the physically based materials and reflects it in the
-- glass and the metal, which is what makes a device read as an object.
local Stage = {}

local SIZE = { width = 2048, height = 1024 }

-- environment(native, Pen) -> image
function Stage.environment(native, Pen)
	local canvas = native.canvas(SIZE.width, SIZE.height)
	local pen = Pen.new(canvas, native)
	local w, h = SIZE.width, SIZE.height
	canvas:clear(0.012, 0.012, 0.016, 1)
	-- Sky to floor: a little lift overhead, darker below the horizon.
	pen:linear(0, 0, 0, h, { 0x1A1A20, 0x0B0B0E, 0x050506, 0x0E0C0A }, { 0, 0.42, 0.55, 1 })
	-- Soft shapes: a light is a glow squashed into a box.
	local function box(cx, cy, rw, rh, color, alpha)
		pen:place({ x = cx, y = cy, sx = rw / 100, sy = rh / 100 }, function()
			pen:glow(0, 0, 100, color, alpha)
		end)
	end
	-- Key: a wide softbox above and in front of the subject.
	box(w * 0.5, h * 0.16, 520, 140, 0xFFFFFF, 1)
	box(w * 0.5, h * 0.16, 300, 70, 0xFFFFFF, 1)
	-- Strip lights left and right behind: long vertical highlights on edges.
	box(w * 0.17, h * 0.42, 46, 300, 0xE8EEFF, 0.95)
	box(w * 0.83, h * 0.42, 46, 300, 0xFFF1E0, 0.9)
	-- Fill behind the camera, dim and wide.
	box(w * 0.0, h * 0.45, 260, 180, 0x9FB4FF, 0.18)
	box(w * 1.0, h * 0.45, 260, 180, 0x9FB4FF, 0.18)
	-- Floor bounce.
	box(w * 0.5, h * 0.86, 900, 120, 0x3A2E24, 0.5)
	return canvas:snapshot()
end

return Stage
