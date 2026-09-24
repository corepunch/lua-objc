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
data.visible = false
local changed, changedRefs = mount:update(data)
t.expect(changed ~= view and changedRefs.button == nil, "structural branch reconciles at template boundary")
t.expect(scope.closed, "removed native callbacks are disposed with their subtree")
t.expect(not data.__baseDir and not data.partial, "template evaluation does not mutate controller data")
file = assert(io.open(path, "w")); file:write('<% error("render failed") %>'); file:close()
local ok = pcall(mount.update, mount, data)
t.expect(not ok, "failed evaluation reports its error")
t.expect(mount.view == changed and host.subviews[1] == changed, "failed update preserves mounted UI")
parent:dispose(); t.expect(mount:isDisposed(), "parent scope disposes nested template mount")
t.assertEqual(#host.subviews, 0, "disposed mount removes native subtree")
t.expect(not pcall(mount.update, mount, data), "disposed mount rejects future updates")
os.remove(path)
os.exit(t.summary() and 0 or 1)
