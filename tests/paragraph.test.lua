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
	<Paragraph id="dropped" text="]] .. PROSE .. [[" size="17" design="serif" dropCap="true" dropCapColor="systemTeal" />
	<Paragraph id="short" text="Dark." size="17" dropCap="true" dropCapLines="3" />
	<Paragraph id="quoted" text="&quot;Hello,&quot; says the troll." size="17" dropCap="true" />
	<Paragraph id="empty" text="" size="17" dropCap="true" />
	<Paragraph id="justified" text="]] .. PROSE .. [[" size="17" alignment="justified" hyphenation="true" />
</VStack>]], {}, ns)

root.size = ns.Size(320, 2000); root:layout(320)
t.assertEqual(refs.plain.size.width, 320, "prose fills the column it is given")
t.expect(refs.plain.size.height > 40, "long prose wraps to several lines at 320pt")
t.expect(refs.leaded.size.height > refs.plain.size.height, "lineSpacing adds leading between lines")
t.expect(refs.dropped.size.height >= refs.plain.size.height,
	"a dropped initial takes line width, so the paragraph is at least as tall")
t.assertEqual(refs.dropped.text, PROSE, "the paragraph keeps its complete text, initial included")
t.expect(refs.dropped.initialView.hidden == false, "a paragraph that begins with a letter drops it")
t.assertEqual(refs.dropped.initialView.letter, "Y", "the dropped initial is the first letter")
t.expect(refs.dropped.initialView.font.pointSize > 17 * 2,
	"the initial is set large enough to span its lines")
t.expect(refs.dropped.textContainer.exclusionPaths[1] ~= nil, "the following lines wrap around the initial")

local lineHeight = refs.plain.font.ascender - refs.plain.font.descender
t.expect(refs.short.size.height >= lineHeight * 3 - 1,
	"a one-line paragraph still reserves the three lines its initial drops through")
t.expect(refs.quoted.initialView.hidden == true, "punctuation is not dropped as an initial")
t.expect(refs.empty.initialView.hidden == true, "an empty paragraph has no initial")
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

-- Text and typography changes re-measure without re-rendering.
refs.short.text = PROSE
root:layout(320)
t.expect(refs.short.size.height > lineHeight * 3, "new text re-measures the paragraph")
t.assertEqual(refs.short.initialView.letter, "Y", "new text drops its own initial")
refs.short.dropCap = false
root:layout(320)
t.expect(refs.short.initialView.hidden == true, "turning dropCap off restores the first letter")

-- A script capital that swashes below its baseline (Snell Roundhand's Y) is
-- scaled by its ink so the whole letter fits the three lines, and its view
-- frames the ink so no stroke is clipped.
local script = xml.render([[<Paragraph text="]] .. PROSE .. [[" size="18" design="serif" lineSpacing="6" dropCap="true" dropCapFontName="SnellRoundhand-Bold" />]], {}, ns)
local host = ns.VStack { script }
host.size = ns.Size(360, 1000); host:layout(360)
local pitch = (script.font.ascender - script.font.descender + script.font.leading) + 6
local ink = script.initialInk
t.expect(ink.origin.y >= 0 and ink.origin.x >= 0, "the initial's ink starts inside the paragraph")
t.expect(ink.origin.y + ink.size.height <= 3 * pitch, "a descending script capital fits within three lines")
t.expect(ink.size.height >= 2 * pitch, "the initial still spans most of its three lines")
local view = script.initialView
t.expect(view.frame.origin.x <= ink.origin.x and view.frame.origin.x + view.frame.size.width >= ink.origin.x + ink.size.width
	and view.frame.origin.y <= ink.origin.y and view.frame.origin.y + view.frame.size.height >= ink.origin.y + ink.size.height,
	"the initial's view frames all of its ink, so nothing is clipped")
local exclusion = script.textContainer.exclusionPaths[1].bounds
t.expect(exclusion.size.height <= 3 * pitch, "exactly three lines wrap beside the initial")

-- Font.smallCaps selects the OpenType small-capital feature.
local caps = ns.Font { size = 13, smallCaps = true, design = "serif" }
local settings = caps.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute
t.expect(settings ~= nil, "smallCaps adds OpenType feature settings to the font")
local label = xml.render([[<Label text="Chapter One" size="13" smallCaps="true" />]], {}, ns)
t.expect(label.font.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute ~= nil,
	"Label smallCaps reaches the native font")
