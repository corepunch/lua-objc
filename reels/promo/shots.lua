-- Bespoke shots drawn with the pen (Reel's `<Draw with="…">`).
local Reel = require("Reel")
local Shape, rgb = Reel.Shape, Reel.rgb
local progress, spring = Reel.curves.progress, Reel.curves.spring

local shots = {}

-- The voice pill under the phone: a microphone, a waveform that follows the
-- speech, and the words appearing as they are recognised. Centred on (0, 0).
local VOICE = { width = 430, height = 76, bars = 22, barWidth = 5, gap = 4, start = 14.1,
	words = { { 14.35, "Add" }, { 14.62, "a" }, { 14.8, "filter." } } }
local TYPE = Reel.Pen.style(30, "semibold", 0xF5F5F7, -0.01)

function shots.voice(pen, t)
	local w, h = VOICE.width, VOICE.height
	pen:save()
	pen:shadow({ dy = 14, blur = 40, color = { 0, 0, 0, 0.5 } })
	pen:fill(Shape.roundedRect(-w / 2, -h / 2, w, h, h / 2), rgb(0x1C1C1E, 0.94))
	pen:shadow()
	pen:stroke(Shape.roundedRect(-w / 2, -h / 2, w, h, h / 2), rgb(0xFFFFFF, 0.12), 1.5)
	-- The microphone, lit while listening.
	pen:fill(Shape.circle(-w / 2 + h / 2, 0, h / 2 - 10), rgb(0x0A84FF))
	pen:symbol("mic.fill", -w / 2 + h / 2, 0, 24, 0xFFFFFF)
	-- The waveform: speech energy rises with each word and settles after.
	local x0 = -w / 2 + h + 6
	local energy = 0
	for _, word in ipairs(VOICE.words) do
		local dt = t - word[1]
		if dt > -0.05 and dt < 0.45 then energy = math.max(energy, math.exp(-math.abs(dt - 0.12) / 0.14)) end
	end
	energy = 0.18 + 0.82 * energy * (1 - progress(t, 15.1, 15.3))
	for i = 0, VOICE.bars - 1 do
		local phase = math.sin(t * 17 + i * 1.7) * 0.5 + math.sin(t * 9.3 + i * 0.9) * 0.5
		local bh = 6 + (h - 32) * energy * (0.35 + 0.65 * math.abs(phase))
		local x = x0 + i * (VOICE.barWidth + VOICE.gap)
		pen:fill(Shape.roundedRect(x, -bh / 2, VOICE.barWidth, bh, VOICE.barWidth / 2), rgb(0xF5F5F7, 0.9))
	end
	-- The transcript, word by word.
	local cursor = x0 + VOICE.bars * (VOICE.barWidth + VOICE.gap) + 10
	for _, word in ipairs(VOICE.words) do
		if t >= word[1] then
			local k = spring(t - word[1], 0.35, 0.7)
			pen:save()
			pen:fade(math.min(1, (t - word[1]) / 0.08))
			pen:translate(0, (1 - k) * 12)
			cursor = cursor + pen:text(word[2], TYPE, cursor, 11, "leading") + 8
			pen:restore()
		end
	end
	pen:restore()
end

return shots
