_G.__headless = true
local t = require('TestKit')
local ns = require('AppKit')
local xml = require('ui.xml')

-- A capped scroll view grows inside its own limit. It does not make the
-- surrounding content-sized stack absorb spare height at its sibling's
-- expense. Content length may change without moving the action offscreen.
local root, refs = xml.render([[<VStack spacing="0">
  <ScrollView id="main" flexGrow="1" flexBasis="0" vertical="true"><Label text="Inventory" /></ScrollView>
  <VStack id="inspector" spacing="8" padding="14">
    <ScrollView id="evidence" vertical="true" maxHeight="144"><Label id="prose" text="Short evidence" lines="0" /></ScrollView>
    <Button id="action" title="Review" />
  </VStack>
</VStack>]],{},ns)
local function check()
	root.size=ns.Size(600,500); root:layout(600)
	local expected=refs.evidence.frame.size.height+refs.action.frame.size.height+8+28
	t.assertEqual(refs.inspector.frame.size.height,expected,'inspector fits actual children and padding')
	t.expect(refs.evidence.frame.size.height <=144,'evidence respects maximum')
	t.expect(refs.main.frame.size.height >280,'uncapped inventory receives remaining space')
end
check()
t.expect(refs.evidence.size.height >= refs.prose.size.height,'short evidence viewport actually contains its text')
local shortHeight=refs.evidence.size.height
refs.prose.text=string.rep('Complete evidence must stay readable through scrolling. ',100)
check()
t.assertEqual(refs.evidence.size.height,144,'long document prefers a usable viewport up to the cap')
t.expect(refs.prose.size.height > refs.evidence.size.height,'remaining long evidence is available through scrolling')
refs.prose.text='Short again'
check()
t.assertEqual(refs.evidence.size.height,shortHeight,'viewport shrinks to short content again')

local function growth(source)
	local view, children=xml.render(source,{},ns)
	view.size=ns.Size(600,500); view:layout(600)
	return children
end
local explicit=growth([[<VStack spacing="0"><VStack id="container" flexGrow="1"><ScrollView vertical="true" maxHeight="144"><Label text="Bounded" /></ScrollView></VStack></VStack>]])
t.assertEqual(explicit.container.size.height,500,'explicit parent growth remains honored with a bounded child')
local unbounded=growth([[<VStack spacing="0"><VStack id="container"><ScrollView id="scroll" vertical="true"><Label text="Unbounded" /></ScrollView></VStack></VStack>]])
t.assertEqual(unbounded.container.size.height,500,'unbounded scroll still propagates parent growth')
t.assertEqual(unbounded.scroll.size.height,500,'unbounded scroll consumes its proposal')
os.exit(t.summary() and 0 or 1)
