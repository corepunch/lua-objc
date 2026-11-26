_G.__headless = true
-- Adventure Arena has one way to get its words: resources.xml in English and
-- resources.<language>.xml for each other language (ui/resources.lua).
local t = require("TestKit")
local xml = require("ui.xml")
local Languages = require("apps.adventure-arena.helpers.Languages")

local PATH = "apps/adventure-arena/resources.xml"
local APP = "apps/adventure-arena/"
local function ids(language)
	local set = {}
	for id, value in pairs(xml.loadResources(PATH, language)) do set[id] = value end
	return set
end
local English = ids(nil)

local function files(command)
	local list = {}
	local pipe = assert(io.popen(command))
	for line in pipe:lines() do table.insert(list, line) end
	pipe:close()
	return list
end
local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("a")
	file:close()
	return text
end

-- Every language has the same strings as English, no more and no less, and
-- each carries the same format placeholders in the same order.
local function placeholders(text)
	local found = {}
	for spec in text:gmatch("%%[%a]") do table.insert(found, spec) end
	return table.concat(found)
end
for _, language in ipairs(Languages.list()) do
	local own = ids(language.id)
	local source = xml.source(PATH:gsub("%.xml$", "." .. language.id .. ".xml"))
	if language.id == "en" then
		t.assertEqual(source, nil, "English is the base resources, not a translation")
	else
		t.expect(source ~= nil, language.id .. " has its own resources file")
		local declared = {}
		for id in (source or ""):gmatch('<String id="([%w_]+)"') do declared[id] = true end
		for id in pairs(English) do
			t.expect(declared[id], language.id .. " translates " .. id)
		end
		for id in pairs(declared) do
			t.expect(English[id] ~= nil, language.id .. " has no string English lacks: " .. id)
		end
		for id, value in pairs(own) do
			t.assertEqual(placeholders(value), placeholders(English[id]), language.id .. " keeps the placeholders of " .. id)
		end
	end
end

-- German words are written, not copied from English (a few are the same word).
local SAME = { genre = true, factGenre = true, factAdventure = false, theme_original = true, spacingNormal = true,
	fontSerif = true, fontSans = true, fontMono = true, factGenre = true }
local German = ids("de")
for id, value in pairs(English) do
	if not SAME[id] then t.expect(German[id] ~= value, "German differs from English for " .. id) end
end

-- Every `@name` and `resources.name` a view or controller uses is declared,
-- and every string is used.
local used = {}
local sources = files("find " .. APP .. "views -name '*.etlua'")
for _, name in ipairs({ "Controller.lua", "Store.lua" }) do table.insert(sources, APP .. name) end
for _, folder in ipairs({ "models", "controllers", "pages", "helpers", "services", "flows" }) do
	for _, path in ipairs(files("find " .. APP .. folder .. " -name '*.lua'")) do table.insert(sources, path) end
end
for _, path in ipairs(sources) do
	local text = read(path)
	-- A template may declare numbers of its own in a <Resources> element.
	local own = {}
	for id in text:gmatch('<%u%l+ id="([%a_][%w_]*)" value=') do own[id] = true end
	for name in text:gmatch('"@([%a_][%w_]*)"') do
		used[name] = true
		t.expect(English[name] ~= nil or own[name], path .. " uses @" .. name .. " which is not declared")
	end
	for name in text:gmatch("%f[%w_]resources%.([%a_][%w_]*)") do
		if name ~= "xml" and name ~= "lua" then
			used[name] = true
			t.expect(English[name] ~= nil, path .. " uses resources." .. name .. " which is not declared")
		end
	end
	for name in text:gmatch("strings%.([%a_][%w_]*)") do
		used[name] = true
		t.expect(English[name] ~= nil, path .. " uses strings." .. name .. " which is not declared")
	end
	-- Names built from an id ("theme_" .. id) and ids a model holds (audienceKids).
	for name in text:gmatch("resources%['([%a_]+)_'") do
		for id in pairs(English) do
			if id:find("^" .. name .. "_") then used[id] = true end
		end
	end
	for name in text:gmatch('title = "([%a]+)"') do used[name] = true end
	for name in text:gmatch('detail = "([%a]+)"') do used[name] = true end
end
for id in pairs(English) do t.expect(used[id], "the string " .. id .. " is used") end

-- No view says a word of its own: what a person reads is a resource.
local VISIBLE = { "text", "title", "label", "placeholder", "accessibilityLabel", "description" }
local ALLOWED = { Aa = true, ["Adventure Arena"] = true }
for _, path in ipairs(files("find " .. APP .. "views -name '*.etlua'")) do
	local text = read(path):gsub("<%%.-%%>", "\1")
	for _, attribute in ipairs(VISIBLE) do
		for value in text:gmatch("[%s]" .. attribute .. '="([^"]*)"') do
			local literal = value ~= "" and not value:find("^@[%a_][%w_]*$") and not value:find("\1", 1, true)
			t.expect(not literal or ALLOWED[value], path .. " hard-codes " .. attribute .. "=\"" .. value .. "\"")
		end
	end
end

os.exit(t.summary() and 0 or 1)
