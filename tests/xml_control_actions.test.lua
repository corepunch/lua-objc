_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local slider, picker = ns.Slider, ns.Picker
local seen = {}

ns.Slider = function(props)
	seen.slider = props.onChange
	return slider(props)
end
ns.Picker = function(props)
	seen.picker = props.action
	return picker(props)
end

local actions = { changed = function() end }
xml.render([[<Slider min="14" max="24" value="17" onChange="changed" />]], {
	actions = actions,
}, ns)
xml.render([[<Picker value="0" onChange="changed"><Option title="System" /><Option title="Serif" /></Picker>]], {
	actions = actions,
}, ns)

t.assertEqual(seen.slider, actions.changed, "XML Slider binds its onChange action")
t.assertEqual(seen.picker, actions.changed, "XML Picker binds its onChange action")

os.exit(t.summary() and 0 or 1)
