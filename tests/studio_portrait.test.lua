_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local Root = require("apps.studio.Controller")

-- An iPad Pro 13-inch in portrait is 1032 points wide. The rail and the
-- agent card must fit at that width: every rail item ends inside the rail,
-- and the card header, which holds the agent, the status and the menu,
-- ends inside the card, which clips its bounds. The header once overflowed
-- there and lost its menu; this pins the fix.
local WIDTH, HEIGHT = 1032, 1376

local root = Root.new()
root.model = { files = { ["demo/playground/Controller.lua"] = "return {}" }, messages = {} }
root.projects = { { id = "HabitTracker", title = "Habit Tracker", icon = "checklist", selected = true } }
root.activeProject = root.projects[1]
root.mode = "chat"
root.actions = root:workspaceActions()
-- A headless window of the portrait size lays the tree out for real.
local config, hostRefs = xml.render('<Window width="' .. WIDTH .. '" height="' .. HEIGHT
	.. '"><VStack id="host" maxWidth="infinity" maxHeight="infinity" /></Window>', {}, ns)
local window = ns.Window(config)
local host = hostRefs.host
root.workspace = Template.new(host, "apps/studio/views/layouts/Workspace.etlua", ns)
root:render()
local refs = root.refs

local function windowX(view)
	local x = 0
	while view and view ~= host do x, view = x + view.frame.origin.x, view.superview end
	return x
end
local function right(view) return windowX(view) + view.frame.size.width end

local hostWidth = host.frame.size.width
t.expect(hostWidth >= WIDTH - 1 and hostWidth <= WIDTH + 1, "the workspace lays out at the portrait width: " .. tostring(hostWidth))
t.expect(refs.projectMenu ~= nil and refs["rail/run"] ~= nil, "the project menu and the actions are on the rail")
local railRight = refs.rail.frame.size.width + 0.5
for _, id in ipairs({ "projectMenu", "rail/run", "rail/commit", "rail/plugins", "rail/settings" }) do
	t.expect(right(refs[id]) <= railRight, id .. " fits the rail: " .. right(refs[id]) .. " of " .. railRight)
end
local cardRight = right(refs.chatCard)
t.expect(refs.conversationMenu ~= nil, "the card header keeps its menu")
t.expect(right(refs.conversationMenu) <= cardRight + 0.5,
	"the conversation menu ends inside the card: " .. right(refs.conversationMenu) .. " of " .. cardRight)
t.expect(windowX(refs.conversationMenu) > windowX(refs.chatCard), "and starts inside it")
t.expect(right(refs.activity) <= windowX(refs.conversationMenu) + 0.5 and windowX(refs.activity) >= right(refs.agentChooser) - 0.5,
	"the status sits between the agent and the menu without overlap")
t.expect(right(refs.previewPane) <= windowX(refs.chatPane) + 0.5, "the stage and the card do not overlap")
t.expect(refs.previewPane.frame.size.width >= 440 - 0.5, "the stage keeps the width the device needs")
t.expect(refs.chatCard.frame.size.width >= 380, "the card keeps a usable width beside it: " .. refs.chatCard.frame.size.width)

os.exit(t.summary() and 0 or 1)
