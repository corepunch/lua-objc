_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write('<VStack><Label id="label" text="<%= title %>"/><% if visible then %><Button id="button" title="Review" action="review"/><% end %></VStack>'); file:close()
local parent = ns.Scope.new()
local host = xml.render('<VStack maxWidth="infinity"/>', {}, ns)
local mount = ns.Scope.withScope(parent, Template.new, host, path, ns)
local called = 0
local data = {title = "First", visible = true, actions = {review = function() called = called + 1 end}}
local view, refs = mount:update(data)
local scope = mount.scope
local description = mount.description
local directData = {title = "Direct"}
xml.describe('<Label text="<%= title %>"/>', directData)
t.expect(directData.partial == nil, "direct descriptions do not inject helpers into caller bindings")
xml.renderFile(path, data, ns)
t.expect(data.__baseDir == nil and data.partial == nil, "direct file rendering also preserves caller data")
mount.dispatch.review(); t.assertEqual(called, 1, "initial action dispatched")
data.actions.review = function() called = called + 10 end
local same, sameRefs = mount:update(data)
t.expect(same == view and sameRefs.label == refs.label, "unchanged description preserves native identity")
mount.dispatch.review(); t.assertEqual(called, 11, "retained native callbacks route to current actions")
local buttonScope = xml.scopeOf(mount.mounted, "button")
local label = refs.label
data.visible = false
local changed, changedRefs = mount:update(data)
t.expect(changed == view and changedRefs.label == label, "a structural change keeps the views it did not change")
t.expect(changedRefs.button == nil and #view.subviews == 1, "a removed branch leaves the stack")
t.expect(buttonScope.closed and not scope.closed, "removed native callbacks are disposed with their subtree only")
data.visible, data.title = true, "Second"
local _, reshown = mount:update(data)
t.expect(reshown.label == label and label.text == "Second", "changed text applies to the existing label")
t.expect(reshown.button ~= nil and view.subviews[2] == reshown.button, "an inserted branch takes its place in the stack")
data.visible = false; mount:update(data)
t.expect(not data.__baseDir and not data.partial, "template evaluation does not mutate controller data")
file = assert(io.open(path, "w")); file:write('<% error("render failed") %>'); file:close()
local ok = pcall(mount.update, mount, data)
t.expect(not ok, "failed evaluation reports its error")
t.expect(mount.view == changed and host.subviews[1] == changed, "failed update preserves mounted UI")
parent:dispose(); t.expect(mount:isDisposed(), "parent scope disposes nested template mount")
t.assertEqual(#host.subviews, 0, "disposed mount removes native subtree")
t.expect(not pcall(mount.update, mount, data), "disposed mount rejects future updates")
os.remove(path)

-- A chip that replaces itself when tapped (a suggestion strip re-rendered by
-- its own action) must not take the work it started with it: a timer begun
-- in the action belongs to the template, not to the rebuilt button node.
local chipPath = os.tmpname() .. ".etlua"
file = assert(io.open(chipPath, "w"))
file:write('<HStack><% for index, title in ipairs(chips) do %><Button id="chip_<%= index %>" title="<%= title %>" action="tap" /><% end %></HStack>'); file:close()
local chipHost = xml.render('<VStack maxWidth="infinity"/>', {}, ns)
local chipOwner = ns.Scope.new()
local chips = ns.Scope.withScope(chipOwner, Template.new, chipHost, chipPath, ns)
local timerFired, chipData = 0, { chips = { "north" } }
chipData.actions = { tap = function()
	require("AppKitNative")._timerAfter(0.01, function() timerFired = timerFired + 1 end)
	chips:update({ chips = {}, actions = chipData.actions })
end }
local _, chipRefs = chips:update(chipData)
local tappedScope = xml.scopeOf(chips.mounted, "chip_1")
ns._invokeAction(chipRefs.chip_1)
t.expect(tappedScope.closed, "the tapped chip was removed by its own action")
require("AppKitNative")._runLoopTick(0.1)
t.assertEqual(timerFired, 1, "a timer started by a replaced control still fires")
chipOwner:dispose()
os.remove(chipPath)
os.exit(t.summary() and 0 or 1)
