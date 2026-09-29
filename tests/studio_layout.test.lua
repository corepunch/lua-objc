_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local Preview = require("apps.studio.models.Preview")
local Chat = require("apps.studio.models.Chat")

local projects = {
	{ id = "StarterApp", title = "Starter App", icon = "app.dashed", selected = true },
	{ id = "HabitTracker", title = "Habit Tracker", icon = "checklist" },
}
local source = xml.describeFile("apps/studio/views/Window.etlua", {
	preview = Preview.presentation(projects),
	chat = Chat.presentation(),
}).source

t.expect(not source:find("nil", 1, true), "partials render instead of inserting nil")
local workspace = assert(source:match('(<HStack id="workspace".-</Window>)'))
local previewAt = workspace:find('id="previewPane"', 1, true)
local chatAt = workspace:find('id="chatPane"', 1, true)
t.expect(previewAt and chatAt and previewAt < chatAt, "preview stays on the left of the chat")
local _, dividers = workspace:gsub('<Divider orientation="vertical"', "")
t.assertEqual(dividers, 1, "one divider separates the two panes")
t.expect(not source:find('id="sidebar"', 1, true), "the navigation sidebar is gone")
t.expect(not source:find('id="toolbar"', 1, true), "the stage owns workspace actions; no separate toolbar strip")

local stage = assert(source:match('(<VStack id="previewPane".-)<VStack id="chatPane"'))
t.expect(stage:find('id="previewPane" padding="16" spacing="12" width="440"', 1, true) ~= nil,
	"the stage is only as wide as the device needs")
t.expect(stage:find('flexGrow="1"', 1, true) ~= nil, "a focused stage can grow once its width is released")
t.expect(not stage:find('title="Share"', 1, true) and not stage:find('title="Deploy"', 1, true),
	"project actions leave the narrow stage bar")
t.expect(stage:find('<Preview id="preview" background="clear"', 1, true) ~= nil,
	"the device sits directly on the stage background")
local stageBar = assert(stage:match('(<HStack id="stageBar".-</HStack>)'))
local barPreview = stage:find('id="stageBar"', 1, true)
local devicePreview = stage:find('<Preview', 1, true)
local deviceBar = stage:find('id="deviceBar"', 1, true)
t.expect(barPreview < devicePreview and devicePreview < deviceBar,
	"glass bars sit above and below the device, never over it")
t.expect(stageBar:find('<Menu id="projectMenu" title="Starter App"', 1, true) ~= nil,
	"the project menu names the selected project")
t.expect(stageBar:find('title="Habit Tracker"', 1, true) ~= nil,
	"the project menu lists every project")
t.expect(stageBar:find('title="Settings"', 1, true) ~= nil,
	"workspace destinations moved into the project menu")
t.expect(stageBar:find('action="reloadPreview" style="glassProminent"', 1, true) ~= nil,
	"Run is the prominent stage action")
t.expect(stageBar:find('action="toggleChat"', 1, true) and stageBar:find('accessibilityLabel="Focus Preview"', 1, true),
	"icon-only chat toggle keeps an accessible name")
t.expect(stageBar:find('id="previewStatus"', 1, true) ~= nil, "preview status is beside the project")

local chat = assert(source:match('(<VStack id="chatPane".-)</HStack>%s*</Window>'))
t.expect(chat:find('id="chatPane" spacing="0" flexGrow="1"', 1, true) ~= nil, "the chat takes the remaining width")
t.expect(chat:find('maxWidth="720"', 1, true) ~= nil, "the conversation keeps a readable measure")
t.expect(chat:find('title="Share"', 1, true) and chat:find('title="Deploy"', 1, true),
	"Share and Deploy live in the chat header")
t.expect(chat:find('<Picker id="chatMode" style="segmented"', 1, true) ~= nil,
	"Chat and Code are a native segmented control")
t.expect(chat:find('<ScrollView id="transcriptScroll" flexGrow="1"', 1, true) ~= nil,
	"the transcript scrolls independently of the composer")
t.expect(chat:find('background="accent" cornerRadius="18"', 1, true) ~= nil, "the request reads as the user's bubble")
t.expect(chat:find('6 files changed', 1, true) and chat:find('+243', 1, true),
	"the change card totals the agent's edits")
t.expect(chat:find('text="Today.etlua"', 1, true) and chat:find('text="views"', 1, true),
	"change rows show the file name with its folder")
t.expect(chat:find('Describe a change…', 1, true) ~= nil, "the composer invites a change")
t.expect(chat:find('accessibilityLabel="Send" style="glassProminent"', 1, true) ~= nil,
	"send is the composer's prominent action")
local composerAt = chat:find('id="composer"', 1, true)
t.expect(composerAt > chat:find('</ScrollView>', 1, true), "the composer stays below the transcript")

local empty = xml.describeFile("apps/studio/views/Window.etlua", {
	preview = Preview.presentation({}),
	chat = Chat.presentation(),
}).source
t.expect(empty:find('title="No Project"', 1, true) ~= nil, "an empty workspace still renders a project menu")
os.exit(t.summary() and 0 or 1)
