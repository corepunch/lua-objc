_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local Toolbar = require("apps.studio.models.Toolbar")
local Preview = require("apps.studio.models.Preview")
local Chat = require("apps.studio.models.Chat")
local Rail = require("apps.studio.models.Rail")
local Theme = require("apps.studio.models.Theme")

local projects = {
	{ id = "StarterApp", title = "Starter App", icon = "rocket.fill", selected = true },
	{ id = "HabitTracker", title = "Habit Tracker", icon = "checklist" },
}
local iconChoices = {
	{ title = "Rocket Sketch", symbol = "pencil.tip.crop.circle", imagePath = "/Documents/StarterApp/ProjectIcons/rocket-sketch.png", selected = false, action = "selectProjectIcon_rocket-sketch" },
}
local window = xml.describeFile("apps/studio/views/layouts/Window.etlua", {canvas = Theme.canvas}).source
local function describe(state)
	state = state or {}
	return xml.describeFile("apps/studio/views/layouts/Workspace.etlua", {
		rail = Rail.presentation(state.mode),
		toolbar = state.toolbar or Toolbar.presentation(projects, iconChoices),
		preview = state.preview or Preview.presentation(),
		chat = state.chat or Chat.presentation(),
	}).source
end
local source = describe()

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

-- Rail, then toolbar over stage and card: the toolbar spans the content
-- beside the rail, as a window toolbar spans the content beside a sidebar.
local railAt = source:find('id="rail"', 1, true)
local toolbarAt = source:find('id="toolbar"', 1, true)
local previewAt = source:find('id="previewPane"', 1, true)
local chatAt = source:find('id="chatPane"', 1, true)
t.expect(railAt and toolbarAt and previewAt and chatAt and railAt < toolbarAt and toolbarAt < previewAt and previewAt < chatAt,
	"rail, toolbar, stage, and agent card follow in that order")
t.expect(source:find('<VStack id="content"[^>]-flexGrow="1"') ~= nil, "the toolbar and panes share one column beside the rail")
t.expect(not source:find('<Divider orientation="vertical" />', 1, true), "the columns float on the canvas; no rule divides them")

local rail = assert(source:match('(<VStack id="rail".-)<VStack id="content"'))
t.expect(rail:find('id="rail" tint="systemIndigo" width="68"', 1, true) ~= nil, "the rail is a narrow icon column")
t.expect(not rail:find('background=', 1, true), "the rail rests on the canvas")
t.expect(not rail:find('title=', 1, true), "rail items are icon-only")
for _, name in ipairs({ "Lua Studio", "Chat, selected", "Code", "Run", "Commit", "Plugins", "Settings" }) do
	t.expect(rail:find('accessibilityLabel="' .. name .. '"', 1, true) ~= nil, "icon-only " .. name .. " keeps an accessible name")
end
t.expect(not rail:find('Templates', 1, true) and not rail:find('Examples', 1, true),
	"projects are made from the project menu; the rail repeats no project action")
t.expect(rail:find('<LinearGradient colors="' .. Theme.brand .. '" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="12" />', 1, true) ~= nil,
	"the brand mark is a gradient tile")
t.expect(rail:find('<ZStack id="rail/chat/on" width="44" height="44" accessibilityLabel="Chat, selected">', 1, true) ~= nil,
	"the selected mode shows its gradient highlight")
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

-- The toolbar holds every window-wide action, on one glass bar.
local toolbar = assert(source:match('(<HStack id="toolbar".-)<HStack id="panes"'))
t.expect(toolbar:find('id="toolbar" tint="systemIndigo" paddingHorizontal="16" paddingTop="16"', 1, true) ~= nil,
	"the toolbar is inset like the stage and the card")
t.expect(toolbar:find('<GlassEffectContainer', 1, true) ~= nil, "the toolbar floats on Liquid Glass")
t.expect(toolbar:find('<Menu id="projectMenu" title="Starter App"', 1, true) ~= nil,
	"the project menu names the selected project")
t.expect(toolbar:find('title="Habit Tracker"', 1, true) ~= nil, "the project menu lists every project")
t.expect(toolbar:find('title="New Project"[^>]-action="newProject"') ~= nil, "the project menu makes a new project")
t.expect(not toolbar:find('title="Settings"', 1, true) and not toolbar:find('title="Plugins"', 1, true),
	"workspace destinations live on the rail")
local _, toolbarButtons = toolbar:gsub('<Button', "")
t.assertEqual(toolbarButtons, 1, "the toolbar holds one button, the chat toggle; Run and Commit are on the rail")
t.expect(not toolbar:find('style="glassProminent"', 1, true), "nothing in the toolbar is prominent")
t.expect(toolbar:find('action="toggleChat"', 1, true) and toolbar:find('accessibilityLabel="Focus Preview"', 1, true),
	"icon-only chat toggle keeps an accessible name")
t.expect(toolbar:find('<SystemImage name="checkmark.circle.fill"', 1, true) ~= nil,
	"the mutable status keeps its symbol as a separate view")
local statusAt = assert(toolbar:find('<Label id="previewStatus"', 1, true))
local statusEnd = assert(toolbar:find('/>', statusAt, true))
t.expect(toolbar:sub(statusAt, statusEnd):find('systemImage=', 1, true) == nil,
	"the status ref points to a text label instead of a composite layout view")
for _, gone in ipairs({ 'title="Share"', 'title="Deploy"', "Toggle Appearance", "Zoom", "iPhone 16", "Reload Preview" }) do
	t.expect(not source:find(gone, 1, true), gone .. " is not offered: nothing it would do exists yet")
end

-- The stage is the device alone.
local stage = assert(source:match('(<VStack id="previewPane".-)<VStack id="chatPane"'))
t.expect(stage:find('id="previewPane" padding="16" spacing="0" width="440"', 1, true) ~= nil,
	"the stage is only as wide as the device needs")
t.expect(not stage:match('id="previewPane"[^>]-background='), "the device stands on the canvas, not a pane fill")
t.expect(not stage:match('<Preview[^>]-tint='), "the previewed app keeps its own accent")
t.expect(stage:find('flexGrow="1"', 1, true) ~= nil, "a focused stage can grow once its width is released")
t.expect(stage:find('<Preview id="preview" background="clear"', 1, true) ~= nil,
	"the device sits directly on the stage background")
t.expect(not stage:find('<Button', 1, true) and not stage:find('<Menu', 1, true), "no bar shares the stage with the device")

-- The card header is the agent and its menu; the composer is a field and Send.
local chat = assert(source:match('(<VStack id="chatPane".-)</HStack>%s*</VStack>%s*</HStack>%s*$'))
t.expect(chat:find('id="chatPane" hidden="false" tint="systemIndigo" paddingVertical="12" paddingTrailing="12" spacing="0" flexGrow="1"', 1, true) ~= nil,
	"the chat takes the remaining width, inset from the window edge")
t.expect(chat:find('id="chatCard"[^>]-background="background" cornerRadius="28" clipsToBounds="true"') ~= nil,
	"the agent lives in a rounded card that clips its panes")
t.expect(chat:find('maxWidth="720"', 1, true) ~= nil, "the conversation keeps a readable measure")
local header = assert(chat:match('(<HStack paddingHorizontal="16".-</HStack>)'))
t.expect(not header:find('<Button', 1, true), "the header has no buttons; project actions are the toolbar's")
t.expect(header:find('<Menu id="conversationMenu"', 1, true) ~= nil, "the header keeps the conversation menu")
t.expect(header:find('title="New Conversation"[^>]-action="newConversation"') and header:find('title="Undo Last Change"[^>]-action="undoChange"')
	and header:find('title="Choose Model…"[^>]-action="openSettings"'), "the menu's items act")
t.expect(not chat:find('<Picker', 1, true), "the rail switches modes; the header has no mode picker")
t.expect(chat:find('<ScrollView id="transcriptScroll" hidden="false" flexGrow="1"', 1, true) ~= nil,
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
t.expect(chat:find('accessibilityLabel="Send" action="send" style="glassProminent"', 1, true) ~= nil,
	"send is the composer's prominent action")
local composer = assert(chat:match('(<GlassEffect cornerRadius="24".-</GlassEffect>)'))
local _, composerButtons = composer:gsub('<Button', "")
t.assertEqual(composerButtons, 1, "the composer offers Send alone; attach and dictate had nothing behind them")
local composerAt = chat:find('id="composer"', 1, true)
t.expect(composerAt > chat:find('</ScrollView>', 1, true), "the composer stays below the transcript")

local empty = describe({ toolbar = Toolbar.presentation({}) })
t.expect(empty:find('title="No Project"', 1, true) ~= nil, "an empty workspace still renders a project menu")
-- The workspace is drawn from its state: the code mode, a hidden chat and a
-- hidden project tree are attributes of the description, not later edits.
local Code = require("apps.studio.models.Code")
local function workspaceWith(state)
	local chat = Chat.presentation(nil, Code.presentation({}))
	chat.mode, chat.hidden, chat.treeHidden = state.mode, state.chatHidden, state.treeHidden
	local toolbar = Toolbar.presentation(projects, iconChoices)
	toolbar.chatHidden = state.chatHidden
	local preview = Preview.presentation()
	preview.chatHidden = state.chatHidden
	return describe({ mode = state.mode, toolbar = toolbar, preview = preview, chat = chat })
end
local code = workspaceWith({ mode = "code" })
t.expect(code:find('id="codePane" hidden="false"', 1, true) and code:find('id="transcriptScroll" hidden="true"', 1, true),
	"code mode shows the code pane and hides the transcript")
local focused = workspaceWith({ mode = "chat", chatHidden = true })
t.expect(focused:find('id="chatPane" hidden="true"', 1, true) ~= nil, "a focused preview hides the chat")
t.expect(not focused:find('id="previewPane"[^>]-width="440"'), "and the stage drops its fixed width")
t.expect(focused:find('accessibilityLabel="Show Chat"', 1, true) ~= nil, "the toggle offers the chat back")
local treeless = workspaceWith({ mode = "code", treeHidden = true })
t.expect(treeless:find('id="treePane" hidden="true"', 1, true) and treeless:find('id="treeDivider" hidden="true"', 1, true),
	"a hidden project tree hides its divider too")

os.exit(t.summary() and 0 or 1)
