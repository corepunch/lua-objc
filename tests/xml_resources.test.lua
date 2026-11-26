-- Resources: constants declared as XML and referenced as `@name`, resolved
-- once when a template renders. `$name` is live data; `@name` is static.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Resources = require("ui.resources")

local app = Resources.fromNodes(xml.parse([[<Resources>
	<Number id="gap" value="10" />
	<String id="title" value="Hello" />
	<Color id="accent" value="systemBlue" />
	<Bool id="muted" value="true" />
</Resources>]]))
t.assertEqual(app.gap, "10", "a Number reads as its attribute text")
t.assertEqual(app.title, "Hello", "a String reads as written")
t.assertEqual(app.muted, "true", "a Bool reads as true or false")

local function render(template, data)
	data = data or {}
	data.resources = data.resources or app
	return xml.render(template, data, ns)
end

local stack = render('<VStack spacing="@gap"><Label text="@title" /></VStack>')
t.assertEqual(stack.spacing, 10, "a numeric attribute takes a Number resource")
t.assertEqual(stack.subviews[1].text, "Hello", "a text attribute takes a String resource")

-- A <Resources> element scopes to its parent, including the parent's own
-- attributes, and overrides what it inherits.
local scoped = render([[<VStack spacing="@gap">
	<Resources><Number id="gap" value="3" /><String id="inner" value="Local" /></Resources>
	<Label text="@inner" />
	<HStack spacing="@gap"><Label text="@title" /></HStack>
</VStack>]])
t.assertEqual(scoped.spacing, 3, "a local resource overrides the app's for its parent")
t.assertEqual(scoped.subviews[1].text, "Local", "a local resource is visible to the siblings")
t.assertEqual(scoped.subviews[2].spacing, 3, "a local resource reaches the subtree")
t.assertEqual(scoped.subviews[2].subviews[1].text, "Hello", "an app resource still reaches a scoped subtree")
local outside = render('<VStack><HStack><Resources><Number id="gap" value="3" /></Resources></HStack><HStack spacing="@gap" /></VStack>')
t.assertEqual(outside.subviews[2].spacing, 10, "a local resource does not leak to a sibling subtree")
t.assertEqual(#outside.subviews, 2, "<Resources> is never a view")

-- Errors.
local function rejects(template, pattern, message, data)
	local ok, err = pcall(render, template, data)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end
rejects('<Label text="@missing" />', "not declared", "an undeclared resource is an error")
t.assertEqual(render('<Label text="@img" />', { resources = {} }).text, "@img",
	"without resources in scope, @ is ordinary text (data such as an npm scope)")
rejects('<Resources><Number id="a" value="x" /></Resources>', "non%-numeric", "a Number must be a number",
	{ resources = {} })
local function declares(source, pattern, message)
	local ok, err = pcall(Resources.fromNodes, xml.parse(source))
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end
declares('<Resources><Bool id="a" value="yes" /></Resources>', "true or false", "a Bool is true or false")
declares('<Resources><Label id="a" value="x" /></Resources>', "not a resource", "only the four kinds are resources")
declares('<Resources><Number value="1" /></Resources>', "needs an id", "a resource needs an id")
declares('<Resources><Number id="a" /></Resources>', "needs a value", "a resource needs a value")
declares('<Resources><Number id="a" value="1" /><Number id="a" value="2" /></Resources>', "twice", "an id is declared once")
declares('<VStack />', "must be <Resources>", "the document root is Resources")

-- An attribute is a literal or exactly one reference.
local literal = render('<Label text="a@gap" />')
t.assertEqual(literal.text, "a@gap", "a reference inside a longer string is a literal")
local mail = render('<Label text="igor@example.com" />')
t.assertEqual(mail.text, "igor@example.com", "an address is a literal")

-- The app's file loads from disk.
local path = os.tmpname()
local file = assert(io.open(path, "w"))
file:write('<Resources><Number id="symbolColumn" value="26" /></Resources>')
file:close()
t.assertEqual(xml.loadResources(path).symbolColumn, "26", "loadResources reads resources.xml")
os.remove(path)

-- A language is a second file beside it whose strings replace the base ones.
local base = os.tmpname()
local de = base .. ".xml"
local function write(name, text)
	local out = assert(io.open(name, "w"))
	out:write(text)
	out:close()
end
write(de, '<Resources><String id="greeting" value="Hello" /><String id="bye" value="Bye" /><Number id="gap" value="4" /></Resources>')
local german = de:gsub("%.xml$", ".de.xml")
write(german, '<Resources><String id="greeting" value="Hallo" /></Resources>')
local loaded = xml.loadResources(de, "de")
t.assertEqual(loaded.greeting, "Hallo", "a language's string replaces the base one")
t.assertEqual(loaded.bye, "Bye", "a string the language leaves out keeps the base")
t.assertEqual(loaded.gap, "4", "other kinds are untouched")
t.assertEqual(xml.loadResources(de, "fr").greeting, "Hello", "a language with no file speaks the base")
t.assertEqual(xml.loadResources(de).greeting, "Hello", "no language is the base")
t.assertEqual(xml.loadResources(de, "de").greeting, "Hallo", "loading again gives the same words")
t.assertEqual(xml.loadResources(de, "").greeting, "Hello", "an empty language is the base")
local label = render('<Label text="@greeting" />', { resources = loaded })
t.assertEqual(label.text, "Hallo", "a template renders with the resources it is given")
write(german, '<Resources><String id="greting" value="Hallo" /></Resources>')
local ok, err = pcall(xml.loadResources, de, "de")
t.expect(not ok and tostring(err):find("greting is translated but not declared", 1, true),
	"a translation of an undeclared id is an error (" .. tostring(err) .. ")")
os.remove(de)
os.remove(german)
os.remove(base)
os.exit(t.summary() and 0 or 1)
