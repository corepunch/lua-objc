_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local PROSE = "You are standing in an open field west of a white house, with a boarded front door. "
	.. "There is a small mailbox here, and a path leads north into a quiet, ancient forest."

local root, refs = xml.render([[
<VStack spacing="0" alignment="leading">
	<Paragraph id="plain" text="]] .. PROSE .. [[" size="17" design="serif" />
	<Paragraph id="leaded" text="]] .. PROSE .. [[" size="17" design="serif" lineSpacing="8" />
	<Paragraph id="short" text="Dark." size="17" />
	<Paragraph id="empty" text="" size="17" />
	<Paragraph id="justified" text="]] .. PROSE .. [[" size="17" alignment="justified" hyphenation="true" />
</VStack>]], {}, ns)

root.size = ns.Size(320, 2000); root:layout(320)
t.assertEqual(refs.plain.size.width, 320, "prose fills the column it is given")
t.expect(refs.plain.size.height > 40, "long prose wraps to several lines at 320pt")
t.expect(refs.leaded.size.height > refs.plain.size.height, "lineSpacing adds leading between lines")
t.assertEqual(refs.plain.text, PROSE, "the paragraph keeps its complete text")
t.assertEqual(#refs.plain.textContainer.exclusionPaths, 0, "every line uses the full text column")
t.assertEqual(refs.empty.size.height, 0, "an empty paragraph takes no height")
t.assertEqual(refs.justified.textAlignment, 3, "justified alignment maps to the native alignment")
t.expect(refs.justified.hyphenation == true, "hyphenation is enabled when requested")
t.expect(refs.plain.selectable == true and refs.plain.editable == false,
	"prose is selectable for Look Up and copy, never editable")
local pitch = math.ceil(refs.short.font.ascender - refs.short.font.descender + refs.short.font.leading)
t.expect(refs.short.size.height > 0 and refs.short.size.height <= pitch + 1,
	"a short paragraph reserves only its text height")

-- Round trip: narrowing the column wraps more lines; widening restores it.
local wide = refs.plain.size.height
root.size = ns.Size(200, 2000); root:layout(200)
t.expect(refs.plain.size.height > wide, "a narrower column wraps into more lines")
root.size = ns.Size(320, 2000); root:layout(320)
t.assertEqual(refs.plain.size.height, wide, "restoring the width restores the height")

-- Text and typography changes re-measure without re-rendering.
refs.short.text = PROSE
root:layout(320)
t.expect(refs.short.size.height > pitch, "new text re-measures the paragraph")
refs.short.text = "Dark."
root:layout(320)
t.expect(refs.short.size.height <= pitch + 1, "shortening the text releases the extra height")
t.assertEqual(refs.plain.size.height, wide, "changing another paragraph preserves the original height")
refs.short.text = ""
root:layout(320)
t.assertEqual(refs.short.size.height, 0, "clearing text releases all paragraph height")

-- Every type size and leading uses the full column without image exclusions.
for _, size in ipairs({ 14, 18, 26 }) do
	for _, lead in ipairs({ 3, 6, 13 }) do
		local paragraph = xml.render('<Paragraph text="' .. PROSE .. '" size="' .. size
			.. '" design="serif" lineSpacing="' .. lead .. '" />', {}, ns)
		local column = ns.VStack { paragraph }
		column.size = ns.Size(360, 1000); column:layout(360)
		t.assertEqual(paragraph.size.width, 360, "typography preserves the full column width")
		t.expect(paragraph.size.height > 0, "typography produces a measured paragraph")
		t.assertEqual(#paragraph.textContainer.exclusionPaths, 0, "typography introduces no image exclusions")
	end
end

-- Font.smallCaps selects the OpenType small-capital feature.
local caps = ns.Font { size = 13, smallCaps = true, design = "serif" }
local settings = caps.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute
t.expect(settings ~= nil, "smallCaps adds OpenType feature settings to the font")
local label = xml.render([[<Label text="Chapter One" size="13" smallCaps="true" />]], {}, ns)
t.expect(label.font.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute ~= nil,
	"Label smallCaps reaches the native font")

os.exit(t.summary() and 0 or 1)
