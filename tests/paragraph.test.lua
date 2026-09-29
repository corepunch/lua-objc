_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local PROSE = "You are standing in an open field west of a white house, with a boarded front door. "
	.. "There is a small mailbox here, and a path leads north into a quiet, ancient forest."

local ICON = "apps/adventure-arena/assets/zork1.jpg"
local root, refs = xml.render([[
<VStack spacing="0" alignment="leading">
	<Paragraph id="plain" text="]] .. PROSE .. [[" size="17" design="serif" />
	<Paragraph id="leaded" text="]] .. PROSE .. [[" size="17" design="serif" lineSpacing="8" />
	<Paragraph id="figured" text="]] .. PROSE .. [[" size="17" design="serif" figure="]] .. ICON .. [[" />
	<Paragraph id="short" text="Dark." size="17" figure="]] .. ICON .. [[" figureLines="3" />
	<Paragraph id="empty" text="" size="17" figure="]] .. ICON .. [[" />
	<Paragraph id="justified" text="]] .. PROSE .. [[" size="17" alignment="justified" hyphenation="true" />
</VStack>]], {}, ns)

root.size = ns.Size(320, 2000); root:layout(320)
t.assertEqual(refs.plain.size.width, 320, "prose fills the column it is given")
t.expect(refs.plain.size.height > 40, "long prose wraps to several lines at 320pt")
t.expect(refs.leaded.size.height > refs.plain.size.height, "lineSpacing adds leading between lines")
t.expect(refs.figured.size.height > refs.plain.size.height,
	"a figure takes line width, so the paragraph wraps into more lines")
t.assertEqual(refs.figured.text, PROSE, "the paragraph keeps its complete text")
t.expect(refs.plain.figureView == nil, "a paragraph without a figure floats nothing")

-- The figure is a square exactly three lines tall at the leading edge, and the
-- lines beside it keep a gap from it.
local pitch = math.ceil(refs.figured.font.ascender - refs.figured.font.descender + refs.figured.font.leading)
local figure = refs.figured.figureView
t.expect(figure ~= nil and figure.hidden == false, "the figure shows beside the text")
t.assertEqual(figure.frame.origin.x, 0, "the figure sits at the leading edge")
t.assertEqual(figure.frame.origin.y, 0, "the figure's top meets the first line's top")
t.assertEqual(figure.frame.size.width, figure.frame.size.height, "the figure is square")
t.expect(math.abs(figure.frame.size.height - 3 * pitch) < 0.5, "the figure spans three lines")
local exclusion = refs.figured.textContainer.exclusionPaths[1].bounds
t.expect(exclusion.size.width > figure.frame.size.width, "wrapped lines keep a gap from the figure")
t.expect(math.abs(exclusion.size.height - 3 * pitch) < 1, "exactly three lines wrap beside the figure")

t.expect(refs.short.size.height >= 3 * pitch - 0.5,
	"a one-line paragraph still reserves the three lines of its figure")
t.assertEqual(refs.empty.size.height, 0, "an empty paragraph takes no height")
t.assertEqual(refs.justified.textAlignment, 3, "justified alignment maps to the native alignment")
t.expect(refs.justified.hyphenation == true, "hyphenation is enabled when requested")
t.expect(refs.plain.selectable == true and refs.plain.editable == false,
	"prose is selectable for Look Up and copy, never editable")

-- Round trip: narrowing the column wraps more lines; widening restores it.
local wide = refs.plain.size.height
root.size = ns.Size(200, 2000); root:layout(200)
t.expect(refs.plain.size.height > wide, "a narrower column wraps into more lines")
root.size = ns.Size(320, 2000); root:layout(320)
t.assertEqual(refs.plain.size.height, wide, "restoring the width restores the height")
t.assertEqual(refs.figured.figureView.frame.origin.x, 0, "layout leaves the figure where the paragraph put it")

-- Text and typography changes re-measure without re-rendering.
refs.short.text = PROSE
root:layout(320)
t.expect(refs.short.size.height > 3 * pitch, "new text re-measures the paragraph")
refs.short.figureLines = 2
root:layout(320)
t.expect(math.abs(refs.short.figureView.frame.size.height - 2 * pitch) < 0.5, "figureLines resizes the figure")
refs.short.figureView = nil
root:layout(320)
t.expect(#refs.short.textContainer.exclusionPaths == 0, "removing the figure returns every line to the margin")

-- Every size and leading keeps the figure within its lines.
for _, size in ipairs({ 14, 18, 26 }) do
	for _, lead in ipairs({ 3, 6, 13 }) do
		local paragraph = xml.render('<Paragraph text="' .. PROSE .. '" size="' .. size
			.. '" design="serif" lineSpacing="' .. lead .. '" figure="' .. ICON .. '" />', {}, ns)
		local column = ns.VStack { paragraph }
		column.size = ns.Size(360, 1000); column:layout(360)
		local linePitch = math.ceil(paragraph.font.ascender - paragraph.font.descender + paragraph.font.leading) + lead
		local side = paragraph.figureView.frame.size.height
		local label = string.format("figure at %dpt, leading %d", size, lead)
		t.expect(math.abs(side - (3 * linePitch - lead)) < 0.5, label .. " spans three lines")
		t.expect(math.abs(paragraph.textContainer.exclusionPaths[1].bounds.size.height - (side + lead / 2)) < 0.5,
			label .. " wraps exactly those lines")
	end
end

-- Font.smallCaps selects the OpenType small-capital feature.
local caps = ns.Font { size = 13, smallCaps = true, design = "serif" }
local settings = caps.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute
t.expect(settings ~= nil, "smallCaps adds OpenType feature settings to the font")
local label = xml.render([[<Label text="Chapter One" size="13" smallCaps="true" />]], {}, ns)
t.expect(label.font.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute ~= nil,
	"Label smallCaps reaches the native font")
