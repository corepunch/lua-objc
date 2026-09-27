_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")

-- Paragraph.revealedCharacters: a typewriter reveal over text that is laid
-- out whole, so lines never reflow; only revealed lines take height.
local PROSE = "You are standing in an open field west of a white house, with a boarded front door. "
	.. "There is a small mailbox here, and a path leads north into a quiet, ancient forest."

local root, refs = xml.render([[
<VStack spacing="0" alignment="leading">
	<Paragraph id="whole" text="]] .. PROSE .. [[" size="17" design="serif" />
	<Paragraph id="typing" text="]] .. PROSE .. [[" size="17" design="serif" revealedCharacters="0" />
	<Paragraph id="dropped" text="]] .. PROSE .. [[" size="17" design="serif" dropCap="true" revealedCharacters="0" />
	<Paragraph id="accents" text="Café — déjà vu 🦉 here." size="17" revealedCharacters="6" />
</VStack>]], {}, ns)
root.size = ns.Size(320, 2000); root:layout(320)

local whole = refs.whole.size.height
local lineHeight = refs.whole.font.ascender - refs.whole.font.descender
t.assertEqual(refs.whole.revealedCharacters, -1, "a paragraph shows its whole text by default")
t.assertEqual(refs.typing.revealedCharacters, 0, "the XML attribute sets the reveal")
t.assertEqual(refs.typing.size.height, 0, "a paragraph that has revealed nothing takes no height")
t.assertEqual(refs.typing.text, PROSE, "the whole text is kept while it is revealed")
t.expect(refs.dropped.initialView.hidden == true, "the initial waits for the first character")

refs.typing.revealedCharacters = 5
root:layout(320)
local oneLine = refs.typing.size.height
t.expect(oneLine > 0 and oneLine < lineHeight * 1.5, "the first characters open one line")
refs.typing.revealedCharacters = 20
root:layout(320)
t.assertEqual(refs.typing.size.height, oneLine, "typing along a line keeps its height")
refs.typing.revealedCharacters = 90
root:layout(320)
t.expect(refs.typing.size.height > oneLine and refs.typing.size.height < whole,
	"a new line adds height, and unrevealed lines add none")
refs.typing.revealedCharacters = utf8.len(PROSE)
root:layout(320)
t.assertEqual(refs.typing.size.height, whole, "a finished reveal measures as whole text")
refs.typing.revealedCharacters = -1
root:layout(320)
t.assertEqual(refs.typing.size.height, whole, "showing everything measures as whole text")
refs.typing.revealedCharacters = 10000
t.assertEqual(refs.typing.revealedCharacters, 10000, "a reveal past the end is kept and shows everything")
refs.typing.revealedCharacters = -7
t.assertEqual(refs.typing.revealedCharacters, -1, "negative reveals mean everything")

refs.dropped.revealedCharacters = 1
root:layout(320)
t.expect(refs.dropped.initialView.hidden == false, "the first character reveals the dropped initial")
t.expect(refs.dropped.size.height >= lineHeight * 3 - 1, "a revealed initial reserves the lines it drops through")

-- Characters count as Lua's utf8.len does, never splitting a surrogate pair.
refs.accents.revealedCharacters = 17
t.assertEqual(refs.accents.revealedCharacters, 17, "scalar counts round-trip")
t.expect(refs.accents.size.height > 0, "a paragraph with multi-byte characters reveals")

-- Round trip: the reveal changes no other property.
t.assertEqual(refs.typing.font.pointSize, 17, "revealing keeps the font")
t.assertEqual(refs.typing.textAlignment, refs.whole.textAlignment, "revealing keeps the alignment")

-- A retained template patches the reveal in place rather than rebuilding.
local host = ns.VStack {}
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write([[<Paragraph id="story" text="<%= text %>" revealedCharacters="<%= shown %>" hidden="<%= shown == 0 and 'true' or 'false' %>" />]])
file:close()
local template = Template.new(host, path, ns)
local _, first = template:update({ text = PROSE, shown = 0 })
local story = first.story
t.expect(story.hidden == true, "a paragraph waiting to type is hidden")
local _, second = template:update({ text = PROSE, shown = 12 })
t.expect(rawequal(second.story, story), "a new reveal patches the paragraph in place")
t.assertEqual(story.revealedCharacters, 12, "the patched reveal applies")
t.expect(story.hidden == false, "a typing paragraph is shown")
template:update({ text = PROSE, shown = -1 })
t.assertEqual(story.revealedCharacters, -1, "finishing reveals the whole paragraph")
template:dispose()
os.remove(path)

os.exit(t.summary() and 0 or 1)
