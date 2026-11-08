_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local Preview = require("apps.studio.helpers.Preview")
local Chat = require("apps.studio.helpers.Chat")
local Rail = require("apps.studio.helpers.Rail")
local Theme = require("apps.studio.helpers.Theme")

local window = xml.describeFile("apps/studio/views/layouts/Window.etlua", {canvas = Theme.canvas}).source
local source = xml.describeFile("apps/studio/views/sections/Workspace.etlua", {
	rail = Rail.presentation(),
	side = { panel = "preview", width = Rail.columnWidth, preview = Preview.presentation() },
	chat = Chat.presentation({ messages = {
		{ role = "user", text = "Build an app" },
		{ role = "agent", text = "Saved", changes = {{path = "views/pages/Today.etlua", added = 3, removed = 1, lines = {"+ new"}}} },
	} }),
}).source

t.expect(not source:find("nil", 1, true), "partials render instead of inserting nil")
local canvas = assert(window:match('(<ZStack id="canvas".-)<VStack id="workspace"'))
t.expect(canvas:find('id="canvas" maxWidth="infinity" maxHeight="infinity" background="secondaryBackground"', 1, true) ~= nil,
	"the canvas washes over the system background, so it follows light and dark")
local _, washes = canvas:gsub('<LinearGradient colors="[%w,]+" startPoint="%a+" endPoint="%a+" opacity="0%.%d+" ignoresSafeArea="top"', "")
t.assertEqual(washes, 2, "two crossing gradients fill the canvas and run under the status bar")
t.expect(canvas:find('colors="' .. Theme.canvas.wash .. '"', 1, true) and canvas:find('colors="' .. Theme.canvas.glow .. '"', 1, true),
	"the canvas takes its colors from the theme")
t.expect(not canvas:find('tint=', 1, true), "the canvas sets no tint, so the previewed app keeps its accent")

local workspace = source
local railAt = workspace:find('id="rail"', 1, true)
local sideAt = workspace:find('id="sidePane"', 1, true)
local chatAt = workspace:find('id="chatPane"', 1, true)
t.expect(railAt and sideAt and chatAt and railAt < sideAt and sideAt < chatAt,
	"rail, side column, and agent card run left to right")
t.expect(not workspace:find('<Divider orientation="vertical" />', 1, true),
	"the columns float on the canvas; no rule divides them")
t.expect(not source:find('id="toolbar"', 1, true), "no separate toolbar strip")

local rail = assert(workspace:match('(<VStack id="rail".-)<VStack id="sidePane"'))
t.expect(rail:find('id="rail" tint="systemIndigo" width="68"', 1, true) ~= nil, "the rail is a narrow icon column")
t.expect(not rail:find('background=', 1, true), "the rail rests on the canvas")
t.expect(not rail:find('title=', 1, true), "rail items are icon-only")
for _, name in ipairs({ "Lua Studio", "Preview, selected", "Files", "Source Control", "Projects", "Templates", "Examples", "Plugins", "Settings" }) do
	t.expect(rail:find('accessibilityLabel="' .. name .. '"', 1, true) ~= nil, "icon-only " .. name .. " keeps an accessible name")
end
t.expect(not rail:find('accessibilityLabel="Chat', 1, true) and not rail:find('accessibilityLabel="Code"', 1, true),
	"the rail chooses side views; the agent card is always beside them")
t.expect(rail:find('<LinearGradient colors="' .. Theme.brand .. '" startPoint="topLeading" endPoint="bottomTrailing" cornerRadius="12" />', 1, true) ~= nil,
	"the brand mark is a gradient tile")
t.expect(rail:find('<ZStack id="rail/preview/on" width="44" height="44" accessibilityLabel="Preview, selected">', 1, true) ~= nil,
	"the selected view shows its gradient highlight")
t.expect(not rail:find('id="rail/preview/off"', 1, true), "and no plain button")
t.expect(not rail:find('id="rail/git/on"', 1, true), "an unselected view has no highlight")
for _, panel in ipairs({ "files", "git", "projects" }) do
	t.expect(rail:find('id="rail/' .. panel .. '/off"[^>]-action="showPanel_' .. panel .. '"') ~= nil,
		"an unselected view is a plain button that shows it: " .. panel)
end
t.expect(rail:find('id="rail/projects/off"', 1, true) < rail:find('<Divider', 1, true)
	and rail:find('<Divider', 1, true) < rail:find('id="rail/templates"', 1, true),
	"a rule separates the views from the catalogs")
t.expect(rail:find('id="rail/plugins"', 1, true) < rail:find('<Spacer />', 1, true)
	and rail:find('<Spacer />', 1, true) < rail:find('id="rail/settings"', 1, true),
	"settings sits at the foot of the rail")
t.expect(not rail:find('id="rail/github"', 1, true), "GitHub lives in Source Control, not on the rail")

local git = Rail.presentation("git").panels
t.assertEqual(git[3].selected, true, "the rail can show Source Control")
local _, selected = (function() local n = 0; for _, p in ipairs(git) do if p.selected then n = n + 1 end end; return nil, n end)()
t.assertEqual(selected, 1, "only one view is selected")

local side = assert(source:match('(<VStack id="sidePane".-)<VStack id="chatPane"'))
t.expect(side:find('<VStack id="sidePane" paddingVertical="12" paddingTrailing="12" spacing="0" maxWidth="440"', 1, true) ~= nil,
	"the side column is only as wide as the device needs, and meets the card edges")
local stage = assert(side:match('(<VStack id="previewPane".*)'))
t.expect(not stage:match('id="previewPane"[^>]-background='), "the device stands on the canvas, not a pane fill")
t.expect(not side:find('id="sideCard"', 1, true), "the preview needs no card")
t.expect(not stage:match('<Preview[^>]-tint='), "the previewed app keeps its own accent")
t.expect(stage:find('<Preview id="preview" background="clear"', 1, true) ~= nil,
	"the device sits directly on the stage background")
local devicePreview = stage:find('<Preview', 1, true)
local deviceBar = assert(stage:match('(<HStack id="deviceBar".-</HStack>)'))
t.expect(devicePreview < stage:find('id="deviceBar"', 1, true),
	"the device leads the stage; one glass bar sits beneath it, never over it")
t.expect(not stage:find('id="stageBar"', 1, true) and not stage:find('id="previewStatus"', 1, true),
	"no bar or status line above the device takes its height")
t.expect(deviceBar:find('<Button id="runButton" accessibilityLabel="Run" systemImage="play.fill" action="reloadPreview" style="glassProminent" />', 1, true) ~= nil,
	"Run is the prominent action of the bar beneath the device")
local _, reloads = deviceBar:gsub('action="reloadPreview"', "")
t.assertEqual(reloads, 1, "Run is the only reload of the bar; no second button repeats it")
t.expect(deviceBar:find('accessibilityLabel="Preview device"', 1, true) < deviceBar:find('id="runButton"', 1, true),
	"Run follows the device it runs on")

local chat = assert(source:match('(<VStack id="chatPane".-)</HStack>%s*$'))
t.expect(chat:find('id="chatPane" tint="systemIndigo" paddingVertical="12" paddingTrailing="12" spacing="0" flexGrow="1"', 1, true) ~= nil,
	"the chat takes the remaining width, inset from the window edge")
t.expect(chat:find('id="chatCard"[^>]-background="background" cornerRadius="28" clipsToBounds="true"') ~= nil,
	"the agent lives in a rounded card that clips its panes")
t.expect(chat:find('maxWidth="720"', 1, true) ~= nil, "the conversation keeps a readable measure")
t.expect(chat:find('accessibilityLabel="Share"', 1, true) and chat:find('accessibilityLabel="Export"', 1, true),
	"Share and Deploy live in the chat header")
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
t.expect(chat:find('1 file changed', 1, true) and chat:find('+3 −1', 1, true),
	"the change card totals the agent's edits")
t.expect(chat:find('text="Today.etlua"', 1, true) and chat:find('text="views/pages"', 1, true),
	"change rows show the file name with its folder")
t.expect(chat:find('Describe a change…', 1, true) ~= nil, "the composer invites a change")
t.expect(chat:find('accessibilityLabel="Send" action="sendMessage" style="glassProminent"', 1, true) ~= nil,
	"send is the composer's prominent action")
local composerAt = chat:find('id="composer"', 1, true)
t.expect(composerAt > chat:find('</ScrollView>', 1, true), "the composer stays below the transcript")

-- The workspace is drawn from its state: the side view and whether the card
-- shows the open file are attributes of the description, not later edits.
local Code = require("apps.studio.helpers.Code")
local Git = require("apps.studio.helpers.Git")
local ProjectList = require("apps.studio.helpers.ProjectList")
local projects = {
	{ id = "StarterApp", title = "Starter App", icon = "paperplane.fill", bundleId = "org.example.starter", selected = true },
	{ id = "HabitTracker", title = "Habit Tracker", icon = "checklist", bundleId = "org.example.habits" },
}
local function workspaceWith(state)
	local code = Code.presentation({ ["demo/playground/Controller.lua"] = "return {}", ["demo/playground/views/pages/Main.etlua"] = "" }, "Controller.lua")
	local chat = Chat.presentation(nil, code)
	chat.mode = state.mode
	return xml.describeFile("apps/studio/views/sections/Workspace.etlua", {
		rail = Rail.presentation(state.panel),
		side = { panel = state.panel, width = Rail.columnWidth, preview = Preview.presentation(),
			files = { projectTitle = "Starter App" }, git = Git.presentation({}),
			projects = ProjectList.presentation(state.projects or projects, {
				{ title = "Rocket Sketch", symbol = "pencil.tip.crop.circle", imagePath = "", selected = true, action = "selectProjectIcon_rocket-sketch" },
			}) },
		chat = chat, code = code, codeFiles = code.files, history = {}, projectRows = ProjectList.rows(state.projects or projects),
		syntaxRules = Code.rules,
	}).source
end
local coding = workspaceWith({ panel = "files", mode = "code" })
t.expect(coding:find('id="codePane" hidden="false"', 1, true) and coding:find('id="transcriptScroll" hidden="true"', 1, true)
	and coding:find('id="composerPane" hidden="true"', 1, true), "an open file replaces the conversation in the card")
t.expect(coding:find('id="closeCode"[^>]-action="showChat"') ~= nil, "the editor leads with a way back to the conversation")
t.expect(not coding:find('id="treePane"', 1, true) and not coding:find('id="treeToggle"', 1, true),
	"the editor has no tree of its own; the Files view is the tree")
t.expect(coding:find('id="rail/files/on"', 1, true) ~= nil, "the rail highlights Files")
t.expect(not coding:find('<Preview', 1, true), "the preview leaves the column while another view shows")
local files = assert(coding:match('(<VStack id="sideCard".-)<VStack id="chatPane"'))
t.expect(files:find('id="sideCard"[^>]-background="background" cornerRadius="28" clipsToBounds="true"') ~= nil,
	"list views sit in a card matching the agent card")
t.expect(files:find('<List id="codeFiles" data="codeFiles" onSelect="selectFile"', 1, true) ~= nil, "Files lists the project and opens a file")
t.expect(files:find('<Column id="name" title="" imageKey="icon" subtitleKey="folder" />', 1, true) ~= nil,
	"a file row shows its symbol, name and folder")
t.expect(files:find('text="Starter App"', 1, true) ~= nil, "Files is titled with the project")

local listed = workspaceWith({ panel = "projects", mode = "chat" })
t.expect(listed:find('<List id="projectList" data="projectRows" onSelect="openProjectRow"', 1, true) ~= nil, "Projects lists and opens projects")
t.expect(listed:find('id="newProjectButton"[^>]-action="newProject"') ~= nil, "Projects makes a new project")
t.expect(listed:find('id="deleteProjectButton"[^>]-role="destructive"[^>]-action="showDeleteProject"') ~= nil, "the current project can be deleted")
t.expect(listed:find('<MenuItem title="Rocket Sketch"[^>]-action="selectProjectIcon_rocket%-sketch"') ~= nil, "the current project takes an icon")
local none = workspaceWith({ panel = "projects", mode = "chat", projects = {} })
t.expect(not none:find('id="deleteProjectButton"', 1, true), "with no current project there is nothing to delete")

local rows = ProjectList.rows(projects)
t.assertEqual(#rows, 2, "every project is a row")
t.assertEqual(rows[1].detail, "Current project", "the open project is marked")
t.assertEqual(rows[2].detail, "org.example.habits", "the others show their bundle identifier")
t.assertEqual(ProjectList.presentation(projects).current.id, "StarterApp", "the selected project is current")
t.assertEqual(ProjectList.presentation({}).current, nil, "no projects, no current project")
t.assertEqual(#ProjectList.rows(nil), 0, "missing projects are safe")

-- Header symbols share one column, so the titles of every view start at one edge.
for _, panel in ipairs({ "files", "git", "projects" }) do
	local view = workspaceWith({ panel = panel, mode = "chat" })
	t.expect(view:find('<SystemImage name="[%w.]+" size="16" width="22" color="secondary" />') ~= nil,
		"the header symbol has a fixed column: " .. panel)
end
os.exit(t.summary() and 0 or 1)
