_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local Projects = require("apps.studio.models.Projects")
local Preview = require("apps.studio.models.Preview")
local Chat = require("apps.studio.models.Chat")
local Rail = require("apps.studio.models.Rail")
local Theme = require("apps.studio.models.Theme")

local projects = {
	{ id = "StarterApp", title = "Starter App", icon = "app.fill", selected = true },
	{ id = "HabitTracker", title = "Habit Tracker", icon = "checklist" },
}
local iconChoices = {
	{ title = "Rocket Sketch", symbol = "pencil.tip.crop.circle", imagePath = "/Documents/StarterApp/ProjectIcons/rocket-sketch.png", selected = false, action = "selectProjectIcon_rocket-sketch" },
}
local window = xml.describeFile("apps/studio/views/layouts/Window.etlua", {canvas = Theme.canvas}).source
local function describe(state)
	state = state or {}
	return xml.describeFile("apps/studio/views/layouts/Workspace.etlua", {
		rail = state.rail or Rail.presentation(state.mode, state.badges, Projects.menu(projects, iconChoices)),
		preview = state.preview or Preview.presentation(),
		chat = state.chat or Chat.presentation(),
	}).source
end
-- The default conversation with a result in the header, so the activity
-- viewer is drawn; at rest it is absent.
local source = describe({ chat = Chat.presentation({ messages = Chat.DEFAULT.messages, status = { text = "Committed 0123456" } }) })
local resting = describe()

t.expect(not source:find("nil", 1, true), "partials render instead of inserting nil")
t.expect(source:find("Use Rocket Sketch Icon", 1, true) ~= nil, "the project menu renders icon choices")
local canvas = assert(window:match('(<ZStack id="canvas".-)<VStack id="workspace"'))
t.expect(canvas:find('id="canvas" maxWidth="infinity" maxHeight="infinity" background="secondaryBackground"', 1, true) ~= nil,
	"the canvas washes over the system background, so it follows light and dark")
local _, washes = canvas:gsub('<LinearGradient colors="[%w,]+" startPoint="%a+" endPoint="%a+" opacity="0%.%d+" ignoresSafeArea="top"', "")
t.assertEqual(washes, 2, "two crossing gradients fill the canvas and run under the status bar")
t.expect(canvas:find('colors="' .. Theme.canvas.wash .. '"', 1, true) and canvas:find('colors="' .. Theme.canvas.glow .. '"', 1, true),
	"the canvas takes its colors from the theme")
t.expect(not canvas:find('tint=', 1, true), "the canvas sets no tint, so the previewed app keeps its accent")

-- Rail, stage and agent card, left to right, with no bar above them.
local railAt = source:find('id="rail"', 1, true)
local previewAt = source:find('id="previewPane"', 1, true)
local chatAt = source:find('id="chatPane"', 1, true)
t.expect(railAt and previewAt and chatAt and railAt < previewAt and previewAt < chatAt,
	"rail, stage, and agent card follow in that order")
t.expect(not source:find('id="toolbar"', 1, true), "no toolbar: the rail and the card hold every control")
t.expect(not source:find('<Divider orientation="vertical" />', 1, true), "the columns float on the canvas; no rule divides them")

-- The rail: the project menu at the top, then modes, actions, destinations and settings.
local rail = assert(source:match('(<VStack id="rail".-)<VStack id="previewPane"'))
t.expect(rail:find('id="rail" tint="systemIndigo" width="68"', 1, true) ~= nil, "the rail is a narrow icon column")
t.expect(not rail:find('background=', 1, true), "the rail rests on the canvas")
t.expect(not rail:find('<Button[^>]-title=') and rail:find('<Menu id="projectMenu" title=""', 1, true) ~= nil, "rail items are icon-only")
for _, name in ipairs({ "Project: Starter App", "Chat, selected", "Code", "Run", "Commit", "Plugins", "Settings" }) do
	t.expect(rail:find('accessibilityLabel="' .. name .. '"', 1, true) ~= nil, "icon-only " .. name .. " keeps an accessible name")
end
local menu = assert(rail:match('(<Menu id="projectMenu".-</Menu>)'))
t.expect(menu:find('<Menu id="projectMenu"[^>]-cornerRadius="14" style="plain"[^>]-width="44" height="44"') ~= nil,
	"the project artwork fills a tile the shape of the other rail items")
t.expect(rail:find('<Menu id="projectMenu"', 1, true) < rail:find('id="rail/chat/on"', 1, true), "the project menu heads the rail")
t.expect(menu:find('title="Habit Tracker"', 1, true) ~= nil, "the project menu lists every project")
t.expect(menu:find('title="New Project"[^>]-action="newProject"') ~= nil, "the project menu makes a new project")
t.expect(not menu:find('title="Settings"', 1, true) and not menu:find('title="Plugins"', 1, true),
	"workspace destinations stay on the rail itself")
t.expect(not rail:find('Templates', 1, true) and not rail:find('Examples', 1, true),
	"projects are made from the project menu; the rail repeats no project action")
t.expect(rail:find('<ZStack id="rail/chat/on" width="44" height="44" accessibilityLabel="Chat, selected">', 1, true) ~= nil,
	"the selected mode shows its gradient highlight")
t.expect(rail:find('<LinearGradient colors="' .. Theme.brand .. '" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="14" />', 1, true) ~= nil,
	"in the brand gradient")
t.expect(not rail:find('id="rail/chat/off"', 1, true), "and no plain button")
t.expect(not rail:find('id="rail/code/on"', 1, true), "an unselected mode has no highlight")
t.expect(rail:find('id="rail/code/off"[^>]-action="showCode"') ~= nil,
	"an unselected mode is a plain button that selects it")
t.expect(rail:find('id="rail/run"[^>]-action="reloadPreview"') ~= nil, "Run reloads the preview from the rail")
t.expect(rail:find('id="rail/commit"[^>]-action="commitProject"') ~= nil, "Commit records the project from the rail")
local _, rules = rail:gsub('<Divider width="24" />', "")
t.assertEqual(rules, 2, "rules separate the modes, the project actions and the destinations")
t.expect(rail:find('id="rail/code/off"', 1, true) < rail:find('id="rail/run"', 1, true)
	and rail:find('id="rail/commit"', 1, true) < rail:find('id="rail/plugins"', 1, true),
	"modes, then project actions, then destinations")
t.expect(rail:find('id="rail/plugins"[^>]-action="openPlugins"') ~= nil, "Plugins opens its sheet")
t.expect(rail:find('id="rail/plugins"', 1, true) < rail:find('<Spacer />', 1, true)
	and rail:find('<Spacer />', 1, true) < rail:find('id="rail/settings"', 1, true),
	"settings sits at the foot of the rail")
t.expect(rail:find('id="rail/settings"[^>]-action="openSettings"') ~= nil, "Settings opens its sheet")

t.assertEqual(Rail.presentation("code").modes[2].selected, true, "the rail can open on the code")
t.assertEqual(Rail.presentation("code").modes[1].selected, false, "only one mode is selected")

-- The rail counts changes on Commit, as the activity bar counts them on Source Control.
t.expect(not rail:find('rail/commit/badge', 1, true), "no changes, no badge")
local railWithBadge = Rail.presentation("chat", { commit = 3 })
t.expect(railWithBadge.actions[2].badge == "3" and railWithBadge.actions[2].label == "Commit, 3 changes", "the badge counts changed files")
t.assertEqual(Rail.presentation("chat", { commit = 1 }).actions[2].label, "Commit, 1 change", "and reads naturally for one")
t.assertEqual(Rail.presentation("chat", { commit = 120 }).actions[2].badge, "99+", "a large count is capped")
local badgedSource = xml.describeFile("apps/studio/views/sections/Rail.etlua", railWithBadge).source
t.expect(badgedSource:find('id="rail/commit/badge"', 1, true) and badgedSource:find('text="3"', 1, true)
	and badgedSource:find('accessibilityLabel="Commit, 3 changes"', 1, true), "the badge is drawn on the Commit item with an accessible count")
for _, gone in ipairs({ 'title="Share"', 'title="Deploy"', "Toggle Appearance", "Zoom", "iPhone 16", "Reload Preview", "toggleChat", "Focus Preview" }) do
	t.expect(not source:find(gone, 1, true), gone .. " is not offered: nothing it would do exists yet")
end

-- The stage is the device alone.
local stage = assert(source:match('(<VStack id="previewPane".-)<VStack id="chatPane"'))
t.expect(stage:find('id="previewPane" padding="16" spacing="0" width="440"', 1, true) ~= nil,
	"the stage is only as wide as the device needs")
t.expect(not stage:match('id="previewPane"[^>]-background='), "the device stands on the canvas, not a pane fill")
t.expect(not stage:match('<Preview[^>]-tint='), "the previewed app keeps its own accent")
t.expect(stage:find('<Preview id="preview" background="clear"', 1, true) ~= nil,
	"the device sits directly on the stage background")
t.expect(not stage:find('<Button', 1, true) and not stage:find('<Menu', 1, true), "no bar shares the stage with the device")

-- The card header is the agent, the activity viewer and the menu; the composer is a field and Send.
local chat = assert(source:match('(<VStack id="chatPane".-)</HStack>%s*$'))
t.expect(chat:find('id="chatPane" tint="systemIndigo" paddingVertical="12" paddingTrailing="12" spacing="0" flexGrow="1"', 1, true) ~= nil,
	"the chat takes the remaining width, inset from the window edge")
t.expect(chat:find('id="chatCard"[^>]-background="background" cornerRadius="28" clipsToBounds="true"') ~= nil,
	"the agent lives in a rounded card that clips its panes")
t.expect(chat:find('maxWidth="720"', 1, true) ~= nil, "the conversation keeps a readable measure")
local header = assert(chat:match('(<HStack paddingHorizontal="16".-</Menu>%s*</HStack>)'))
local _, headerButtons = header:gsub('<Button', "")
t.assertEqual(headerButtons, 1, "the header has one button, the agent itself; project actions are the rail's")
t.expect(header:find('id="agentChooser"[^>]-action="openSettings"') ~= nil, "tapping the agent opens Settings")
t.expect(header:find('<HStack id="activity"', 1, true) ~= nil, "a result sits in an activity viewer, as in Xcode")
t.expect(not resting:find('id="activity"', 1, true), "at rest the header is the agent and its menu alone")
t.expect(header:find('<SystemImage id="activitySymbol" name="checkmark.circle.fill"', 1, true) ~= nil,
	"the mutable status keeps its symbol as a separate view")
local statusAt = assert(header:find('<Label id="previewStatus"', 1, true))
local statusEnd = assert(header:find('/>', statusAt, true))
t.expect(header:sub(statusAt, statusEnd):find('systemImage=', 1, true) == nil,
	"the status ref points to a text label instead of a composite layout view")
t.expect(header:find('id="agentChooser"', 1, true) < header:find('id="activity"', 1, true)
	and header:find('id="activity"', 1, true) < header:find('<Menu id="conversationMenu"', 1, true),
	"agent, status, then the menu")
t.expect(header:find('title="New Conversation"[^>]-action="newConversation"') and header:find('title="Undo Last Change"[^>]-action="undoChange"')
	and header:find('title="Choose Model…"[^>]-action="openSettings"'), "the menu's items act")
local busySource = describe({ chat = Chat.presentation({ messages = {}, status = { text = "Thinking…", busy = true } }) })
t.expect(busySource:find('<ProgressView id="activitySpinner" indeterminate="true"', 1, true) ~= nil
	and not busySource:find('id="activitySymbol"', 1, true), "a working agent shows a spinner in place of the symbol")
local problemSource = describe({ chat = Chat.presentation({ messages = {}, status = { text = "Add your OpenAI API key in Settings", tone = "problem" } }) })
t.expect(problemSource:find('id="activitySymbol" name="exclamationmark.triangle.fill"', 1, true) ~= nil,
	"a refusal or failure shows a warning symbol")
t.expect(not chat:find('<Picker', 1, true), "the rail switches modes; the header has no mode picker")
t.expect(chat:find('<ScrollView id="transcriptScroll" hidden="false" flexGrow="1"', 1, true) ~= nil,
	"the transcript scrolls independently of the composer")
t.expect(chat:find('id="codePane" hidden="true"', 1, true) and chat:find('syntaxRules="syntaxRules"', 1, true),
	"Code mode starts hidden and binds Lua supplied syntax rules")
t.expect(chat:find('<FlowStack', 1, true) ~= nil and not chat:find('id="welcomePane"', 1, true),
	"once a conversation starts, the chips sit above the composer")
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
t.expect(chat:find('accessibilityLabel="Send" action="send" style="glassProminent"', 1, true) ~= nil,
	"send is the composer's prominent action")
t.expect(chat:find('id="sendButton"[^>]-disabled="true"') ~= nil, "and waits for a draft")
local drafted = Chat.presentation({ messages = Chat.DEFAULT.messages, draft = "Make it blue" })
t.expect(describe({ chat = drafted }):find('id="sendButton"[^>]-disabled="false"') ~= nil, "a draft enables it")
local composer = assert(chat:match('(<GlassEffect cornerRadius="24".-</GlassEffect>)'))
local _, composerButtons = composer:gsub('<Button', "")
t.assertEqual(composerButtons, 1, "the composer offers Send alone; attach and dictate had nothing behind them")
local composerAt = chat:find('id="composer"', 1, true)
t.expect(composerAt > chat:find('</ScrollView>', 1, true), "the composer stays below the transcript")

local empty = describe({ rail = Rail.presentation(nil, nil, Projects.menu({})) })
t.expect(empty:find('accessibilityLabel="Project: No Project"', 1, true) ~= nil, "an empty workspace still renders a project menu")
-- The workspace is drawn from its state: the code mode and a hidden project
-- tree are attributes of the description, not later edits.
local Code = require("apps.studio.models.Code")
local function workspaceWith(state)
	local chat = Chat.presentation(nil, Code.presentation({}))
	chat.mode, chat.treeHidden = state.mode, state.treeHidden
	return describe({ mode = state.mode, chat = chat })
end
local code = workspaceWith({ mode = "code" })
t.expect(code:find('id="codePane" hidden="false"', 1, true) and code:find('id="transcriptScroll" hidden="true"', 1, true),
	"code mode shows the code pane and hides the transcript")
local treeless = workspaceWith({ mode = "code", treeHidden = true })
t.expect(treeless:find('id="treePane" hidden="true"', 1, true) and treeless:find('id="treeDivider" hidden="true"', 1, true),
	"a hidden project tree hides its divider too")

os.exit(t.summary() and 0 or 1)
