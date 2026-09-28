_G.__headless = true
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local t = require("TestKit")

-- Toggle style="button": SwiftUI `.toggleStyle(.button)`, a lit pad.
local changes = {}
local pad = ns.Toggle({label = "Kick", is_on = true, style = "button", systemImage = "circle.fill",
	tint = "systemPink", onChange = function(on) table.insert(changes, on) end})
t.assertEqual(pad.state, 1, "a button-style toggle starts in its state")
t.expect(pad.bezelColor ~= nil, "an on pad is lit with its tint")
t.expect(pad.image ~= nil, "the SF Symbol sits above the label")
pad.state = 0
bridge._invokeAction(pad)
t.assertEqual(pad.bezelColor, nil, "switching off unlights the pad")
t.assertEqual(changes[1], false, "onChange receives the new state")
pad.state = 1
bridge._invokeAction(pad)
t.expect(pad.bezelColor ~= nil, "switching on lights it again")
t.assertEqual(changes[2], true, "and reports it")
local unlit = ns.Toggle({label = "Ghosts", is_on = false, style = "button", tint = "systemPink"})
t.assertEqual(unlit.bezelColor, nil, "an off pad starts unlit")
local plain = ns.Toggle({label = "Ride", is_on = true, style = "button"})
t.assertEqual(plain.bezelColor, nil, "an untinted pad uses the system accent")
local checkbox = ns.Toggle({label = "Snare", is_on = false, tint = "systemTeal"})
t.expect(checkbox.bezelColor ~= nil, "a checkbox keeps its tint in both states")

local parsed, refs = xml.render(
	'<HStack><Toggle id="p" style="button" label="Pads" systemImage="cloud.fill" tint="systemPurple" value="true" width="86" height="62" /></HStack>', {}, ns)
t.expect(parsed ~= nil and refs.p.bezelColor ~= nil, "<Toggle style=\"button\"> renders a lit pad")
ns._parityMeasure(parsed, {}, {width = 200, height = 80})
t.assertSize(refs.p, 86, 62, "a pad takes its template size")

-- symbolSize scales the pad's SF Symbol; without it the symbol follows the
-- label font. The cell centres the symbol and label on their ink.
local small = ns.Toggle({label = "Kick", style = "button", systemImage = "circle.fill"})
local large = ns.Toggle({label = "Kick", style = "button", systemImage = "circle.fill", symbolSize = 16})
t.assertEqual(small.image.size.width, 15, "a pad symbol defaults to the label font size")
t.assertEqual(large.image.size.width, 19, "symbolSize enlarges it by about a quarter")
t.expect(large.intrinsicContentSize.height > small.intrinsicContentSize.height, "a larger symbol grows the pad's natural height")
t.assertEqual(large.cell.className, "LuaToggleButtonCell", "pads draw with the ink-centring cell")
t.assertEqual(large.title, "Kick", "the label survives the custom cell")
t.assertThrows(function() ns.Toggle({label = "x", style = "button", systemImage = "circle", symbolSize = 0}) end,
	"a zero symbolSize is rejected")
local sized = xml.render('<Toggle style="button" label="Arp" systemImage="pianokeys" symbolSize="16" />', {}, ns)
t.assertEqual(sized.image.size.width > 15, true, "<Toggle symbolSize> reaches the native symbol")

-- Slider style="level": an editable native fill bar.
local values = {}
local level = ns.Slider({style = "level", min = 160, max = 180, value = 174, tint = "systemOrange",
	onChange = function(v) table.insert(values, v) end})
t.assertEqual(level.minValue, 160, "a level bar keeps the slider range")
t.assertEqual(level.doubleValue, 174, "and value")
t.expect(level.editable, "a level bar is editable")
t.expect(level.fillColor ~= nil, "tint fills the bar")
level.doubleValue = 170
bridge._invokeAction(level)
t.assertEqual(values[1], 170, "dragging reports the value like a slider")
local clamped = ns.Slider({style = "level", min = 0, max = 1, value = 3})
t.assertEqual(clamped.doubleValue, 1, "initial values clamp to the range")
t.assertThrows(function() ns.Slider({style = "knob"}) end, "unknown slider styles are rejected")
local bar = xml.render('<Slider style="level" min="0" max="1" value="0.4" tint="systemCyan" />', {}, ns)
t.expect(bar.editable and bar.fillColor ~= nil, "<Slider style=\"level\"> renders an editable tinted bar")

os.exit(t.summary() and 0 or 1)
