_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")

-- Paragraph.revealedCharacters: a typewriter reveal over text that is laid
-- out whole, so lines never reflow, and that takes its whole height from
-- the first character, so a page makes room for it once.
local PROSE = "You are standing in an open field west of a white house, with a boarded front door. "
	.. "There is a small mailbox here, and a path leads north into a quiet, ancient forest."

local root, refs = xml.render([[
<VStack spacing="0" alignment="leading">
	<Paragraph id="whole" text="]] .. PROSE .. [[" size="17" design="serif" />
	<Paragraph id="typing" text="]] .. PROSE .. [[" size="17" design="serif" revealedCharacters="0" />
	<Paragraph id="figured" text="]] .. PROSE .. [[" size="17" design="serif" figure="apps/adventure-arena/assets/zork1.jpg" revealedCharacters="0" />
	<Paragraph id="accents" text="Café — déjà vu 🦉 here." size="17" revealedCharacters="6" />
</VStack>]], {}, ns)
root.size = ns.Size(320, 2000); root:layout(320)

local whole = refs.whole.size.height
local lineHeight = refs.whole.font.ascender - refs.whole.font.descender
t.assertEqual(refs.whole.revealedCharacters, -1, "a paragraph shows its whole text by default")
t.assertEqual(refs.typing.revealedCharacters, 0, "the XML attribute sets the reveal")
t.assertEqual(refs.typing.size.height, whole, "a paragraph that has revealed nothing already takes its whole height")
local figured = refs.figured.size.height
t.expect(figured >= lineHeight * 3 - 1, "a waiting figure reserves the lines it spans")
t.assertEqual(refs.typing.text, PROSE, "the whole text is kept while it is revealed")
t.expect(refs.figured.figureView.hidden == true, "the figure waits for the first character")

local below = refs.figured.frame.origin.y
for _, shown in ipairs { 5, 20, 90 } do
	refs.typing.revealedCharacters = shown
	root:layout(320)
	t.assertEqual(refs.typing.size.height, whole, "typing never changes the paragraph's height")
	t.assertEqual(refs.figured.frame.origin.y, below, "typing never moves what follows")
end
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

refs.figured.revealedCharacters = 1
root:layout(320)
t.expect(refs.figured.figureView.hidden == false, "the first character reveals the figure")
t.assertEqual(refs.figured.size.height, figured, "revealing the figure keeps the paragraph's height")

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
file:write([[<Paragraph id="story" text="<%= text %>" revealedCharacters="<%= shown %>" />]])
file:close()
local template = Template.new(host, path, ns)
local _, first = template:update({ text = PROSE, shown = 0 })
local story = first.story
t.assertEqual(story.revealedCharacters, 0, "a paragraph waiting to type shows nothing")
local _, second = template:update({ text = PROSE, shown = 12 })
t.expect(rawequal(second.story, story), "a new reveal patches the paragraph in place")
t.assertEqual(story.revealedCharacters, 12, "the patched reveal applies")
template:update({ text = PROSE, shown = -1 })
t.assertEqual(story.revealedCharacters, -1, "finishing reveals the whole paragraph")
template:dispose()
os.remove(path)

os.exit(t.summary() and 0 or 1)
