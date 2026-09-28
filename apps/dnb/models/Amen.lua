-- The Amen break, recreated: the four-bar drum solo from The Winstons'
-- "Amen, Brother" (1969) that jungle and drum & bass were built on. The
-- Synth renders these hits once, at the record's tempo, into one loop; the
-- Composer plays it back in 16th-note slices, pitched up to the track's
-- tempo the way a sampler plays a sped-up break, and rearranges slices for
-- chops. Steps are 16ths; "ride" is the ride cymbal on the eighths.
local Amen = {}

Amen.bpm = 137
Amen.bars = 4
Amen.slices = Amen.bars * 16

-- {step, voice, velocity} per bar. Bars one and two are the straight groove,
-- bar three delays the last snare, bar four is the famous syncopated turn
-- with the crash.
Amen.pattern = {
	{{0, "kick", 1}, {2, "kick", 0.9}, {4, "snare", 1}, {7, "snare", 0.55}, {9, "snare", 0.6},
		{10, "kick", 0.9}, {12, "snare", 1}, {15, "snare", 0.55}},
	{{0, "kick", 1}, {2, "kick", 0.9}, {4, "snare", 1}, {7, "snare", 0.55}, {9, "snare", 0.6},
		{10, "kick", 0.9}, {12, "snare", 1}, {15, "snare", 0.55}},
	{{0, "kick", 1}, {2, "kick", 0.9}, {4, "snare", 1}, {7, "snare", 0.55}, {9, "snare", 0.6},
		{10, "kick", 0.9}, {14, "snare", 1}},
	{{2, "snare", 0.6}, {4, "snare", 1}, {7, "snare", 0.55}, {9, "snare", 0.6}, {10, "kick", 0.9},
		{10, "crash", 0.8}, {11, "kick", 0.7}, {14, "snare", 1}},
}

-- Slices that open on a full snare hit, for stutter chops.
Amen.snareSlices = {}
for bar, hits in ipairs(Amen.pattern) do
	for _, hit in ipairs(hits) do
		if hit[2] == "snare" and hit[3] >= 1 then table.insert(Amen.snareSlices, (bar - 1) * 16 + hit[1]) end
	end
end

return Amen
