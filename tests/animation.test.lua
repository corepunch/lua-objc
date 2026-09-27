_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local Motion = require("ui.animation")
local Animation, AnyTransition = ns.Animation, ns.AnyTransition

-- Motion runs as if Reduce Motion were off unless a test turns it on.
ns._motionOverrideReduceMotion(false)
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1e-6) end
local function animations(view)
	local result = ns._motionAnimations(view)
	result.arcs = nil
	return result
end

-- ── Animation values mirror SwiftUI's ─────────────────────────────────────
local easeInOut = Animation.easeInOut(0.4)
t.assertEqual(easeInOut.kind, "timing", "curves are timing animations")
t.expect(easeInOut.duration == 0.4 and easeInOut.x1 == 0.42 and easeInOut.x2 == 0.58, "easeInOut keeps its duration and control points")
t.assertEqual(Animation.linear().duration, 0.35, "curves default to SwiftUI's 0.35 seconds")
t.expect(Animation.easeIn().x2 == 1 and Animation.easeOut().x1 == 0, "easeIn and easeOut have one-sided curves")
local spring = Animation.spring({response = 0.5, dampingFraction = 0.8})
t.expect(near(spring.stiffness, (2 * math.pi / 0.5) ^ 2) and near(spring.damping, 4 * math.pi * 0.8 / 0.5),
	"response and damping fraction become stiffness and damping")
t.expect(near(Animation.spring(0.5, 0.3).dampingFraction, 0.7), "a bounce of 0.3 is a damping fraction of 0.7")
t.expect(near(Animation.spring({duration = 0.5, bounce = -0.5}).dampingFraction, 2), "a negative bounce overdamps")
t.expect(Animation.smooth().bounce == 0 and Animation.snappy().bounce == 0.15 and Animation.bouncy().bounce == 0.3,
	"smooth, snappy and bouncy are SwiftUI's presets")
t.expect(near(Animation.bouncy({extraBounce = 0.1}).bounce, 0.4), "presets accept extra bounce")
t.assertEqual(Animation.interpolatingSpring(170, 15).stiffness, 170, "interpolatingSpring keeps its physics")
t.assertEqual(Animation.default.kind, "spring", "the default animation is a spring")
local modified = Animation.easeOut(0.2):delay(0.1):speed(2):repeatCount(3, false)
t.expect(modified.startDelay == 0.1 and modified.speedFactor == 2 and modified.repeats == 3 and not modified.autoreverses,
	"delay, speed and repeatCount chain")
t.expect(Animation.linear():repeatForever().repeats == -1 and Animation.linear():repeatForever().autoreverses,
	"repeatForever autoreverses by default")
t.expect(Animation.easeOut(0.2).startDelay == 0, "modifiers return new values")
t.expect(not pcall(Animation.spring, {duration = 0.5, bounce = 1}), "a bounce must stay below 1")
t.expect(not pcall(Animation.linear().speed, Animation.linear(), 0), "speed must be positive")

-- Parsing, for XML attributes.
t.assertEqual(Animation.parse("spring").kind, "spring", "a bare name parses")
local parsed = Animation.parse("easeInOut(0.3).delay(0.1).repeatForever(false)")
t.expect(parsed.duration == 0.3 and parsed.startDelay == 0.1 and parsed.repeats == -1 and not parsed.autoreverses,
	"calls and modifiers parse")
t.expect(near(Animation.parse("bouncy(0.6)").response, 0.6), "preset durations parse")
t.expect(Animation.parse("timingCurve(0.2, 0, 0, 1, 0.5)").x1 == 0.2, "timing curves parse")
t.expect(not pcall(Animation.parse, "wobble"), "unknown animations fail loudly")
t.expect(not pcall(Animation.parse, "linear.shake(1)"), "unknown modifiers fail loudly")
t.expect(not pcall(Animation.parse, "linear(0.3"), "unbalanced calls fail loudly")

-- Curve and spring math, used to sample keyframes.
t.expect(near(Motion.bezier(0, 0, 1, 1, 0.3), 0.3, 1e-4), "a linear curve is the identity")
t.expect(Motion.bezier(0.42, 0, 0.58, 1, 0.25) < 0.25 and near(Motion.bezier(0.42, 0, 0.58, 1, 0.5), 0.5, 1e-4),
	"easeInOut starts slowly and is symmetric")
local critical = Animation.spring(0.5, 0)
t.expect(Motion.springProgress(critical, 0) == 0 and near(Motion.springProgress(critical, 3), 1, 1e-3),
	"a spring starts at rest and settles at its target")
local peak, overshoots = 0, false
for step = 1, 100 do peak = math.max(peak, Motion.springProgress(Animation.bouncy(), step / 100)) end
t.expect(peak > 1, "a bouncy spring overshoots")
for step = 1, 100 do overshoots = overshoots or Motion.springProgress(critical, step / 100) > 1 + 1e-9 end
t.expect(not overshoots, "a spring without bounce never overshoots")

-- ── Transitions ──────────────────────────────────────────────────────────
t.assertEqual(AnyTransition.opacity.insertion.opacity, 0, "opacity fades in")
t.expect(AnyTransition.slide.insertion.edge == "leading" and AnyTransition.slide.removal.edge == "trailing",
	"slide enters from the leading edge and leaves by the trailing edge")
local push = AnyTransition.push("trailing")
t.expect(push.insertion.edge == "trailing" and push.removal.edge == "leading" and push.removal.opacity == 0,
	"push leaves toward the opposite edge, fading")
local combined = AnyTransition.parse("opacity+scale(0.8)")
t.expect(combined.insertion.opacity == 0 and combined.insertion.scale == 0.8, "combined transitions merge")
local asym = AnyTransition.parse("asymmetric(move(top), opacity)")
t.expect(asym.insertion.edge == "top" and asym.removal.opacity == 0 and asym.removal.edge == nil,
	"asymmetric transitions keep separate insertion and removal")
t.expect(AnyTransition.parse("offset(0, 20)").insertion.offsetY == 20, "offsets parse")
t.expect(not pcall(AnyTransition.parse, "spin"), "unknown transitions fail loudly")
t.expect(not pcall(AnyTransition.move, "sideways"), "unknown edges fail loudly")

-- ── Keyframes ────────────────────────────────────────────────────────────
local track = {{type = "linear", value = 10, duration = 1}, {type = "move", value = 0, duration = 0}, {type = "linear", value = 4, duration = 1}}
t.assertEqual(Motion.trackValue(track, 0, 0.5), 5, "linear keyframes interpolate from the resting value")
t.assertEqual(Motion.trackValue(track, 0, 1), 0, "move keyframes jump")
t.assertEqual(Motion.trackValue(track, 0, 1.5), 2, "later keyframes start from the jump")
t.assertEqual(Motion.trackValue(track, 0, 5), 4, "the last value holds")
local cubic = {{type = "cubic", value = 1, duration = 1}, {type = "cubic", value = 0, duration = 1}}
t.expect(near(Motion.trackValue(cubic, 0, 1), 1, 1e-9) and Motion.trackValue(cubic, 0, 0.5) > 0, "cubic keyframes pass through their values")
local samples = Motion.sampleKeyframes({tracks = {scaleEffect = {{type = "spring", value = 1.4, duration = 0.5}}, offsetY = {{value = -20, duration = 0.25}}}})
t.expect(samples.count == 31 and samples.duration == 0.5, "keyframes sample at 60 per second over the longest track")
t.expect(samples.scaleEffect[1] == 1 and near(samples.offsetY[16], -20), "tracks start at rest and hold their end")
t.expect(not pcall(Motion.sampleKeyframes, {tracks = {width = {{value = 1, duration = 1}}}}), "only animatable properties take keyframes")

-- ── withAnimation ────────────────────────────────────────────────────────
-- Views animate on screen: Core Animation drops animations of layers that
-- are in no window, so each fixture is a window's content.
local windows = {}
local function stack(children)
	local view = ns.VStack { spacing = 0, alignment = "leading" }
	for _, child in ipairs(children) do view:add(child) end
	table.insert(windows, ns.Window { title = "Motion", width = 240, height = 320, content = view })
	return view
end
-- Whichever of a stack's views moved animates its position; which one moves
-- depends on the stack's orientation, not on the engine.
local function moved(...)
	for _, view in ipairs({...}) do
		local found = animations(view).position
		if found then return found end
	end
end
local first = ns.Text { "First", size = 13 }
local second = ns.Text { "Second", size = 13 }
local column = stack({first, second})
local before = {first.frameInWindow.origin.y, second.frameInWindow.origin.y}
local ran = 0
local result = ns.withAnimation(Animation.spring(0.4, 0.2), function() ran = ran + 1; first.fixedHeight = 60; return "done" end)
t.expect(ran == 1 and result == "done", "withAnimation runs its body once and returns its results")
t.expect(first.frame.size.height == 60 and (first.frameInWindow.origin.y ~= before[1] or second.frameInWindow.origin.y ~= before[2]),
	"layout applies at once: model values are final")
local moves = {position = moved(first, second, column)}
t.expect(moves.position ~= nil, "views moved by the change animate their position")
t.assertEqual(moves.position and moves.position.kind, "spring", "springs animate with CASpringAnimation")
t.expect(moves.position and near(moves.position.stiffness, Animation.spring(0.4, 0.2).stiffness, 1e-3), "the spring keeps SwiftUI's stiffness")
ns._motionSettle()
t.expect(next(animations(second)) == nil, "settling finishes every animation")

local completed = 0
ns.withAnimation(Animation.easeOut(0.2):delay(0.1):repeatCount(2), function() first.opacity = 0.5 end, function() completed = completed + 1 end)
local fade = animations(first).opacity
t.expect(fade and fade.kind == "timing" and near(fade.from, 1) and near(fade.to, 0.5), "opacity animates from its old value")
t.expect(fade and fade.repeatCount == 2 and fade.autoreverses and fade.delay > 0.05, "delay and repetition reach Core Animation")
t.assertEqual(completed, 0, "completion waits for the animation")
ns._motionSettle()
t.assertEqual(completed, 1, "completion runs once the animation finishes")
ns.withAnimation(Animation.linear(), function() end, function() completed = completed + 1 end)
ns._motionSettle()
t.assertEqual(completed, 2, "completion runs even when nothing changed")

ns.withAnimation(nil, function() first.opacity = 1 end)
t.expect(animations(first).opacity == nil and first.opacity == 1, "withAnimation(nil) applies changes without animating")
ns.withTransaction(ns.Transaction({animation = Animation.linear(), disablesAnimations = true}), function() first.fixedHeight = 30 end)
t.expect(animations(second).position == nil, "a transaction can disable animations")
ns.withAnimation(Animation.linear(1), function()
	ns.withAnimation(Animation.spring(), function() first.opacity = 0.2 end)
	second.opacity = 0.4
end)
t.assertEqual(animations(first).opacity and animations(first).opacity.kind, "spring", "an inner transaction animates its own changes")
t.assertEqual(animations(second).opacity and animations(second).opacity.kind, "timing", "the outer transaction animates the rest")
ns._motionSettle()
first.opacity, second.opacity = 1, 1
t.expect(not pcall(ns.withAnimation, Animation.linear(), function() error("boom") end), "errors inside withAnimation propagate")
t.expect(not pcall(ns.withAnimation, Animation.linear()), "withAnimation requires a body")

-- Visual modifiers compose into one transform about the view's centre.
local badge = ns.Text { "Badge", size = 13 }
stack({badge})
ns.withAnimation(Animation.easeInOut(0.3), function() badge.scaleEffect = 1.5; badge.rotationEffect = 90; badge.offsetY = 10 end)
t.expect(badge.scaleEffect == 1.5 and badge.rotationEffect == 90 and badge.offsetY == 10, "scale, rotation and offset are view properties")
local turn = animations(badge).transform
t.expect(turn and near(turn.from.scale, 1) and near(turn.to.scale, 1.5, 1e-3), "effects animate the layer transform")
ns._motionSettle()

-- Reduce Motion keeps fades but makes movement immediate.
ns._motionOverrideReduceMotion(true)
ns.withAnimation(Animation.spring(), function() first.fixedHeight = 70; first.opacity = 0.6 end)
t.expect(animations(second).position == nil, "Reduce Motion moves views without animating")
t.expect(animations(first).opacity ~= nil, "Reduce Motion still fades")
ns._motionSettle()
t.assertEqual(ns.reduceMotion(), true, "reduceMotion reports the setting")
ns._motionOverrideReduceMotion(false)
first.opacity = 1

-- Content transitions roll numbers and fade text.
local count = ns.Text { "9", size = 13 }
stack({count})
ns.contentTransition(count, "numericText")
ns.withAnimation(Animation.snappy(), function() count.text = "10" end)
local roll = animations(count).contents
t.expect(roll and roll.kind == "transition" and roll.type == "push", "numeric text rolls to its new value")
ns._motionSettle()
t.expect(not pcall(ns.contentTransition, count, "spin"), "unknown content transitions fail loudly")

-- Hidden views with a transition play it, as SwiftUI's `if` does.
local panel = ns.Text { "Panel", size = 13 }
local after = ns.Text { "After", size = 13 }
stack({panel, after})
ns.transition(panel, "opacity+scale(0.9)")
ns.withAnimation(Animation.easeInOut(0.2), function() panel.hidden = true end)
t.expect(ns._motionIsLeaving(panel) and not panel.hidden, "hiding plays the removal transition first")
t.expect(animations(panel).opacity ~= nil and animations(panel).transform ~= nil, "the removal fades and scales")
t.expect(moved(after, after.superview) ~= nil or animations(after.superview).bounds ~= nil, "siblings close the gap at once")
ns._motionSettle()
t.expect(panel.hidden and not ns._motionIsLeaving(panel), "the view hides when its removal finishes")
ns.withAnimation(Animation.easeInOut(0.2), function() panel.hidden = false end)
t.expect(not panel.hidden and animations(panel).opacity ~= nil, "showing plays the insertion transition")
ns._motionSettle()
panel.hidden = true
t.expect(panel.hidden, "without a transaction hiding is immediate")

-- Keyframe and phase animations.
local heart = ns.Text { "♥", size = 13 }
stack({heart})
local keyframesDone = false
ns.keyframeAnimation(heart, {tracks = {scaleEffect = {{type = "spring", value = 1.3, duration = 0.2}, {type = "linear", value = 1, duration = 0.2}}}},
	function() keyframesDone = true end)
local beat = animations(heart)["keyframes.transform"]
t.expect(beat and beat.kind == "keyframes" and beat.count == 25 and near(beat.duration, 0.4), "keyframes play as one sampled animation")
ns._motionSettle()
t.expect(keyframesDone, "keyframe completion runs")
local phases = ns.phaseAnimation(heart, {phases = {{opacity = 1}, {opacity = 0.3}}, animation = "easeInOut(0.2)"})
t.expect(near(heart.opacity, 0.3, 1e-3) and animations(heart).opacity ~= nil, "phase animation moves to the second phase")
ns._motionSettle()
t.expect(near(heart.opacity, 1, 1e-3), "the next phase follows when one finishes")
phases.cancel()
ns._motionSettle()
t.expect(near(heart.opacity, 1, 1e-3), "a cancelled phase animation stops")
t.expect(not pcall(ns.phaseAnimation, heart, {phases = {{opacity = 1}}}), "phase animation needs two phases")

-- SF Symbol effects.
local symbol = ns.SystemImage { "heart.fill", size = 17 }
t.expect(pcall(ns.symbolEffect, symbol, "bounce"), "discrete symbol effects play")
t.expect(pcall(ns.symbolEffect, symbol, "pulse", {repeating = true}), "indefinite symbol effects play")
t.expect(pcall(ns.symbolEffect, symbol, nil), "symbol effects can be removed")
t.expect(not pcall(ns.symbolEffect, symbol, "explode"), "unknown symbol effects fail loudly")
t.expect(not pcall(ns.symbolEffect, ns.VStack {}, "bounce"), "symbol effects need an image view")

-- ── Templates reconcile inside the transaction ─────────────────────────
local host = stack({})
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write([[<VStack id="root" spacing="4">
  <Label id="title" text="<%= title %>" />
  <% for _, item in ipairs(items) do %>
  <Label id="item_<%= item %>" text="<%= item %>" transition="opacity" />
  <% end %>
  <Label id="count" text="<%= #items %>" animation="bouncy" animationValue="<%= #items %>" />
</VStack>]])
file:close()
local template = Template.new(host, path, ns)
local root, refs = template:update({title = "One", items = {"a", "b"}})
local a, b, title = refs.item_a, refs.item_b, refs.title
t.expect(next(animations(a)) == nil, "the first render outside a transaction does not animate")
ns.withAnimation(Animation.smooth(), function() template:update({title = "Two", items = {"b", "c"}}) end)
local current = template.refs
t.expect(template.view == root and current.title == title and title.text == "Two", "reconciling keeps and patches existing views")
t.expect(current.item_b == b and current.item_c ~= nil and current.item_a == nil, "keyed children are kept, inserted and removed")
t.expect(ns._motionIsLeaving(a), "a removed child plays its removal transition")
t.expect(animations(current.item_c).opacity ~= nil, "an inserted child plays its insertion transition")
t.expect(moved(b, current.item_c, current.title, root) ~= nil or animations(root).bounds ~= nil, "kept children slide to their new places")
ns._motionSettle()
t.expect(a.superview == nil, "the removed child leaves when its transition ends")
t.assertEqual(#root.subviews, 4, "the stack holds the kept and inserted children")
template:update({title = "Two", items = {"b", "c", "d"}})
t.expect(animations(template.refs.item_d).opacity ~= nil, "a changed animationValue animates the update without withAnimation")
ns._motionSettle()
template:update({title = "Three", items = {"b", "c", "d"}})
t.expect(next(animations(title)) == nil and title.text == "Three", "an unchanged animationValue does not animate")
template:dispose()
os.remove(path)

-- XML attributes reach the views.
local _, rendered = xml.render('<Label id="faded" text="x" opacity="0.5" scaleEffect="1.2" rotationEffect="15" offsetX="4" offsetY="6" />', {}, ns)
t.expect(near(rendered.faded.opacity, 0.5, 1e-3) and rendered.faded.scaleEffect == 1.2 and rendered.faded.rotationEffect == 15
	and rendered.faded.offsetX == 4 and rendered.faded.offsetY == 6, "visual modifiers are XML attributes")
t.expect(pcall(xml.render, [[<VStack>
  <Label text="x" transition="slide" matchedGeometry="hero" contentTransition="numericText" />
  <SystemImage name="bell" symbolEffect="wiggle" symbolEffectValue="1" />
  <SystemImage name="wifi" symbolEffect="variableColor" />
</VStack>]], {}, ns), "motion attributes render")
t.expect(not pcall(xml.render, '<Label text="x" transition="spin" />', {}, ns), "a misspelt transition fails at render time")

-- UIKit shares the engine and the API.
local uikit = assert(io.open("lua/embedded/UIKit.lua")):read("*a")
t.expect(uikit:find('require("ui.animation").install(UIKit, bridge)', 1, true) ~= nil, "UIKit installs the same animation API")
local uikitBridge = assert(io.open("src/uikit/bridge.m")):read("*a")
t.expect(uikitBridge:find('#include "../shared/motion.m"', 1, true) ~= nil and uikitBridge:find("LUA_OBJC_MOTION_FUNCTIONS", 1, true) ~= nil,
	"UIKit compiles and registers the shared motion engine")

ns._motionOverrideReduceMotion(nil)
os.exit(t.summary() and 0 or 1)
