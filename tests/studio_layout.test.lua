_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local Preview = require("apps.studio.models.Preview")
local Chat = require("apps.studio.models.Chat")
local Rail = require("apps.studio.models.Rail")
local RailController = require("apps.studio.controllers.RailController")
local Theme = require("apps.studio.models.Theme")

local projects = {
	{ id = "StarterApp", title = "Starter App", icon = "rocket.fill", selected = true },
	{ id = "HabitTracker", title = "Habit Tracker", icon = "checklist" },
}
local source = xml.describeFile("apps/studio/views/Window.etlua", {
	canvas = Theme.canvas,
	rail = Rail.presentation(),
	preview = Preview.presentation(projects, {
		{ title = "Rocket Sketch", symbol = "pencil.tip.crop.circle", imagePath = "/Documents/StarterApp/ProjectIcons/rocket-sketch.png", selected = false, action = "selectProjectIcon_rocket-sketch" },
	}),
	chat = Chat.presentation(),
}).source

t.expect(not source:find("nil", 1, true), "partials render instead of inserting nil")
t.expect(source:find("Use Rocket Sketch Icon", 1, true) ~= nil, "the project menu renders icon choices")
local canvas = assert(source:match('(<ZStack id="canvas".-)<HStack id="workspace"'))
t.expect(canvas:find('id="canvas" maxWidth="infinity" maxHeight="infinity" background="secondaryBackground"', 1, true) ~= nil,
	"the canvas washes over the system background, so it follows light and dark")
local _, washes = canvas:gsub('<LinearGradient colors="[%w,]+" startPoint="%a+" endPoint="%a+" opacity="0%.%d+" ignoresSafeArea="top"', "")
t.assertEqual(washes, 2, "two crossing gradients fill the canvas and run under the status bar")
t.expect(canvas:find('colors="' .. Theme.canvas.wash .. '"', 1, true) and canvas:find('colors="' .. Theme.canvas.glow .. '"', 1, true),
	"the canvas takes its colors from the theme")
t.expect(not canvas:find('tint=', 1, true), "the canvas sets no tint, so the previewed app keeps its accent")

local workspace = assert(source:match('(<HStack id="workspace".-</Window>)'))
local railAt = workspace:find('id="rail"', 1, true)
local previewAt = workspace:find('id="previewPane"', 1, true)
local chatAt = workspace:find('id="chatPane"', 1, true)
t.expect(railAt and previewAt and chatAt and railAt < previewAt and previewAt < chatAt,
	"rail, stage, and agent card run left to right")
t.expect(not workspace:find('<Divider orientation="vertical" />', 1, true),
	"the columns float on the canvas; no rule divides them")
t.expect(not source:find('id="toolbar"', 1, true), "the stage owns workspace actions; no separate toolbar strip")

local rail = assert(workspace:match('(<VStack id="rail".-)<VStack id="previewPane"'))
t.expect(rail:find('id="rail" tint="systemIndigo" width="68"', 1, true) ~= nil, "the rail is a narrow icon column")
t.expect(not rail:find('background=', 1, true), "the rail rests on the canvas")
t.expect(not rail:find('title=', 1, true), "rail items are icon-only")
for _, name in ipairs({ "Lua Studio", "Chat", "Code", "Templates", "Examples", "Plugins", "Settings" }) do
	t.expect(rail:find('accessibilityLabel="' .. name .. '"', 1, true) ~= nil, "icon-only " .. name .. " keeps an accessible name")
end
t.expect(rail:find('<LinearGradient colors="' .. Theme.brand .. '" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="12" />', 1, true) ~= nil,
	"the brand mark is a gradient tile")
t.expect(rail:find('<ZStack id="rail/chat/on" width="44" height="44" hidden="false">', 1, true) ~= nil,
	"the selected mode shows its gradient highlight")
t.expect(rail:find('id="rail/chat/off"[^>]-action="showChat"[^>]-hidden="true"') ~= nil,
	"the selected mode hides its plain button")
t.expect(rail:find('<ZStack id="rail/code/on" width="44" height="44" hidden="true">', 1, true) ~= nil,
	"an unselected mode hides its highlight")
t.expect(rail:find('id="rail/code/off"[^>]-action="showCode"[^>]-hidden="false"') ~= nil,
	"an unselected mode is a plain button that selects it")
t.expect(rail:find('id="rail/plugins"', 1, true) < rail:find('<Spacer />', 1, true)
	and rail:find('<Spacer />', 1, true) < rail:find('id="rail/settings"', 1, true),
	"settings sits at the foot of the rail")

-- The rail highlight follows the mode: exactly one of each pair is visible.
local railController = RailController.new()
railController:presentation()
local refs = {}
for _, id in ipairs({ "rail/chat/on", "rail/chat/off", "rail/code/on", "rail/code/off" }) do refs[id] = {} end
t.assertEqual(railController:select(refs, 1), "code", "mode index 1 is the code")
t.expect(refs["rail/code/on"].hidden == false and refs["rail/code/off"].hidden == true, "code takes the highlight")
t.expect(refs["rail/chat/on"].hidden == true and refs["rail/chat/off"].hidden == false, "chat gives the highlight up")
t.assertEqual(railController:select(refs, 0), "chat", "mode index 0 is the chat")
t.expect(refs["rail/chat/on"].hidden == false and refs["rail/code/on"].hidden == true, "the highlight returns to chat")
t.assertEqual(railController:select(refs, 7), nil, "an unknown mode is refused")
t.expect(refs["rail/chat/on"].hidden == false, "a refused mode leaves the highlight alone")
t.assertEqual(Rail.presentation("code").modes[2].selected, true, "the rail can open on the code")
t.assertEqual(Rail.presentation("code").modes[1].selected, false, "only one mode is selected")

local stage = assert(source:match('(<VStack id="previewPane".-)<VStack id="chatPane"'))
t.expect(stage:find('id="previewPane" padding="16" spacing="12" width="440"', 1, true) ~= nil,
	"the stage is only as wide as the device needs")
t.expect(not stage:match('id="previewPane"[^>]-background='), "the device stands on the canvas, not a pane fill")
t.expect(not stage:match('<Preview[^>]-tint='), "the previewed app keeps its own accent")
t.expect(stage:find('flexGrow="1"', 1, true) ~= nil, "a focused stage can grow once its width is released")
t.expect(not stage:find('title="Share"', 1, true) and not stage:find('title="Deploy"', 1, true),
	"project actions leave the narrow stage bar")
t.expect(stage:find('<Preview id="preview" background="clear"', 1, true) ~= nil,
	"the device sits directly on the stage background")
local stageBar = assert(stage:match('(<HStack id="stageBar".-<Button id="chatVisibility".-/>)'))
local barPreview = stage:find('id="stageBar"', 1, true)
local devicePreview = stage:find('<Preview', 1, true)
local deviceBar = stage:find('id="deviceBar"', 1, true)
t.expect(barPreview < devicePreview and devicePreview < deviceBar,
	"glass bars sit above and below the device, never over it")
t.expect(stageBar:find('<Menu id="projectMenu" title="Starter App"', 1, true) ~= nil,
	"the project menu names the selected project")
t.expect(stageBar:find('title="Habit Tracker"', 1, true) ~= nil,
	"the project menu lists every project")
t.expect(stageBar:find('title="New Project"', 1, true) ~= nil, "the project menu makes a new project")
t.expect(not stageBar:find('title="Settings"', 1, true) and not stageBar:find('title="Plugins"', 1, true),
	"workspace destinations moved to the rail")
t.expect(stageBar:find('action="reloadPreview" style="glassProminent"', 1, true) ~= nil,
	"Run is the prominent stage action")
t.expect(stageBar:find('action="toggleChat"', 1, true) and stageBar:find('accessibilityLabel="Focus Preview"', 1, true),
	"icon-only chat toggle keeps an accessible name")
t.expect(stageBar:find('<SystemImage name="checkmark.circle.fill"', 1, true) ~= nil,
	"the mutable preview status keeps its symbol as a separate view")
local statusAt = assert(stageBar:find('<Label id="previewStatus"', 1, true))
local statusEnd = assert(stageBar:find('/>', statusAt, true))
t.expect(stageBar:sub(statusAt, statusEnd):find('systemImage=', 1, true) == nil,
	"the status ref points to a text label instead of a composite layout view")

local chat = assert(source:match('(<VStack id="chatPane".-)</HStack>%s*</ZStack>%s*</Window>'))
t.expect(chat:find('id="chatPane" tint="systemIndigo" paddingVertical="12" paddingTrailing="12" spacing="0" flexGrow="1"', 1, true) ~= nil,
	"the chat takes the remaining width, inset from the window edge")
t.expect(chat:find('id="chatCard"[^>]-background="background" cornerRadius="28" clipsToBounds="true"') ~= nil,
	"the agent lives in a rounded card that clips its panes")
t.expect(chat:find('maxWidth="720"', 1, true) ~= nil, "the conversation keeps a readable measure")
t.expect(chat:find('title="Share"', 1, true) and chat:find('title="Deploy"', 1, true),
	"Share and Deploy live in the chat header")
t.expect(not chat:find('<Picker', 1, true), "the rail switches modes; the header has no mode picker")
t.expect(chat:find('<ScrollView id="transcriptScroll" flexGrow="1"', 1, true) ~= nil,
	"the transcript scrolls independently of the composer")
t.expect(chat:find('id="codePane" hidden="true"', 1, true) and chat:find('syntaxRules="syntaxRules"', 1, true),
	"Code mode starts hidden and binds Lua supplied syntax rules")
local bubble = assert(chat:match('(<ZStack id="bubble/1".-</ZStack>)'))
t.expect(bubble:find('id="bubble/1" flexGrow="0" flexShrink="1" fixedSize="vertical"', 1, true) ~= nil,
	"the bubble hugs its text instead of growing with its gradient")
t.expect(bubble:find('<LinearGradient colors="' .. Theme.brand .. '" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="18" />', 1, true) ~= nil,
	"the request reads as the user's bubble, in the brand gradient")
t.expect(chat:find('<ZStack width="36" height="36">%s*<LinearGradient colors="[%w,]+" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="18" />') ~= nil,
	"the agent wears its gradient avatar in the header")
t.expect(chat:find('<ZStack width="26" height="26">%s*<LinearGradient colors="[%w,]+" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="13" />') ~= nil,
	"the agent wears its gradient avatar beside its turn")
t.expect(chat:find('7 files changed', 1, true) and chat:find('+291', 1, true),
	"the change card totals the agent's edits")
t.expect(chat:find('text="Today.etlua"', 1, true) and chat:find('text="views"', 1, true),
	"change rows show the file name with its folder")
t.expect(chat:find('Describe a change…', 1, true) ~= nil, "the composer invites a change")
t.expect(chat:find('accessibilityLabel="Send" style="glassProminent"', 1, true) ~= nil,
	"send is the composer's prominent action")
local composerAt = chat:find('id="composer"', 1, true)
t.expect(composerAt > chat:find('</ScrollView>', 1, true), "the composer stays below the transcript")

local empty = xml.describeFile("apps/studio/views/Window.etlua", {
	canvas = Theme.canvas,
	rail = Rail.presentation(),
	preview = Preview.presentation({}),
	chat = Chat.presentation(),
}).source
t.expect(empty:find('title="No Project"', 1, true) ~= nil, "an empty workspace still renders a project menu")
os.exit(t.summary() and 0 or 1)
