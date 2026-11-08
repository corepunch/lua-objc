_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local xml = require("ui.xml")
local Model = require("test.studio-phone.Model")

local model = Model.new(ns._readFile)
t.assertEqual(model:status().title, "Preview updated", "the capsule reports the last edit")
t.expect(model:status().detail:find("2 files changed, +12 −3", 1, true) ~= nil, "with its file count and delta")
t.expect(model:send("   ") == nil, "an empty draft sends nothing")
t.expect(model:send("Sort unfinished first"), "a draft sends")
t.assertEqual(#model.messages, 4, "the user turn and the reply both join the conversation")
t.assertEqual(model.draft, "", "and the draft clears")
model:toggle("water")
t.assertEqual(model:progress().done, 3, "a habit toggles in the model")
t.expect(model:selectFile("views/Today.etlua") and model:code().language == "etlua", "selecting a template changes the code page")
t.expect(not model:selectFile("nope.lua"), "unknown files are refused")

local window = xml.describeFile("test/studio-phone/views/layouts/Window.etlua", { app = model:app() }).source
t.expect(window:find('<TabView id="app"', 1, true) ~= nil, "the project runs in its own tab bar")
t.expect(window:find('<VStack id="stage" maxWidth="infinity" maxHeight="infinity" />', 1, true) ~= nil, "the Today tab hosts the stage template")
local accessory = assert(window:match('<TabAccessory>(.-)</TabAccessory>'), "Studio takes the tab bar accessory slot")
t.expect(accessory:find('id="chrome"', 1, true) ~= nil, "and the accessory hosts the capsule template")
t.expect(not window:find('<GlassEffect', 1, true), "the accessory supplies the glass; nothing floats over the project")

local chrome = xml.describeFile("test/studio-phone/views/sections/Chrome.etlua", {
	status = model:status(), brand = "a,b", tint = "systemIndigo", actions = {} }).source
t.expect(chrome:find('<HStack id="capsule"', 1, true) ~= nil, "the capsule is one row")
t.expect(not chrome:match('id="capsule"[^>]-background='), "with no fill of its own")
t.expect(chrome:find('onTap="openChat"', 1, true) ~= nil, "a tap on it opens the conversation")
t.expect(chrome:find('text="Preview updated"', 1, true) ~= nil, "and it reports the last edit")

local shell = xml.describeFile("test/studio-phone/views/sheets/Shell.etlua", { project = Model.project, projects = Model.projects, actions = {} }).source
t.expect(shell:find('<NavigationStack id="chatNav" title="Habit Garden" subtitle="openrouter/free"', 1, true) ~= nil,
	"the sheet is titled with the project and its model")
t.expect(shell:find('placement="topBarLeading"', 1, true) < shell:find('id="projectMenu"', 1, true), "the project menu leads the sheet bar")
t.expect(shell:find('action="showCode"', 1, true) ~= nil and shell:find('systemItem="done"', 1, true) ~= nil, "code and Done trail")

local chat = xml.describeFile("test/studio-phone/views/sheets/Chat.etlua",
	require("apps.studio.helpers.Chat").presentation({ messages = model.messages })).source
t.expect(chat:find('<SafeAreaInset edge="bottom"', 1, true) ~= nil, "the composer sits in the bottom inset, above the keyboard")
t.expect(chat:find('horizontal="true"', 1, true) ~= nil, "suggestions scroll sideways on a phone")
t.expect(select(2, chat:gsub('2 files changed', '')) == 1, "the edit renders as one change card")
