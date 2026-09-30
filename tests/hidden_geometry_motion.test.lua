_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
ns._motionOverrideReduceMotion(false)
local root, refs = xml.render([[<ZStack width="400" height="300">
	<VStack id="page" hidden="true" maxWidth="infinity" maxHeight="infinity" transition="move(trailing)">
		<Label id="label" text="First appearance" />
		<Spacer />
	</VStack>
</ZStack>]], {}, ns)
local window = ns.Window { title = "Hidden geometry", width = 400, height = 300, content = root }
ns.withAnimation(ns.Animation.linear(0.2), function() refs.page.hidden = false end)
for _, view in ipairs({refs.page, refs.label}) do
	local animations = ns._motionAnimations(view)
	t.expect(animations.position == nil and animations.bounds == nil, "newly visible geometry does not animate from unlaid-out frames")
end
t.expect(ns._motionAnimations(refs.page).transform ~= nil, "the page keeps its entrance transition")
ns._motionSettle()
ns.withAnimation(ns.Animation.linear(0.2), function() refs.page.hidden = true end)
ns._motionSettle()
ns.withAnimation(ns.Animation.linear(0.2), function() refs.page.hidden = false end)
t.expect(ns._motionAnimations(refs.label).position == nil, "later visits also keep child geometry steady")
ns._motionSettle()
os.exit(t.summary() and 0 or 1)
