-- demo/todo: the model's queries and mutations, and the window the
-- controller builds from its templates (the promo reel captures it).
_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Model = require("demo.todo.Model")
local Controller = require("demo.todo.Controller")

local model = Model.new()
local view = model:presentation()
t.assertEqual(#view.tasks, 9, "every sample task shows under All")
t.assertEqual(#view.open + #view.completed, #view.tasks, "open and completed partition the tasks")
t.assertEqual(view.progress.done, 4, "four sample tasks are done")
t.expect(math.abs(view.progress.share - 4 / 9) < 1e-9, "progress is a share of the day")
t.assertEqual(view.filter, 0, "the picker starts on All (0-based)")

model:toggle(2)
t.expect(model:find(2).done, "toggling checks a task off")
t.assertEqual(model:presentation().progress.done, 5, "and moves the progress")
model:toggle(2)
t.expect(not model:find(2).done, "toggling again reopens it")

model:setFilter(3)
view = model:presentation()
t.assertEqual(#view.tasks, 2, "Flagged shows the flagged tasks only")
t.assertEqual(view.progress.total, 9, "progress always covers the whole day")
model:setFilter(2)
t.assertEqual(#model:presentation().completed, 0, "Open hides completed tasks")
model:setFilter(99)
t.assertEqual(model.filter, 2, "an unknown filter is ignored")

local lists = Model.new():lists()
t.assertEqual(lists[1].badge, "5", "Today's badge counts open tasks")
t.expect(lists[4].section, "project lists sit under a section header")
t.assertEqual(#lists, 8, "three smart lists, a header and four projects")

local empty = Model.new({}):presentation()
t.assertEqual(empty.progress.share, 0, "an empty day has no progress and no division by zero")

-- The real window, headless.
local controller = Controller.new()
local window = controller:createWindow()
t.expect(window ~= nil, "the controller opens a window")
t.expect(controller.sidebar ~= nil, "the Mac window has a source-list sidebar")
local refs = controller.content.refs
for _, id in ipairs({ "header", "filter", "progress", "tasks", "completed" }) do
	t.expect(refs[id] ~= nil, "the content has #" .. id .. " for reel captures")
end
controller:toggle(4)
t.expect(controller.model:find(4).done, "a checkbox action reaches the model")
controller:setFilter(3)
t.assertEqual(controller.model.filter, 3, "the filter action reaches the model")

-- UIKit parity the demo relies on: a plain symbol button draws in its tint
-- and a GroupBox fills with the secondary background, as on AppKit.
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("a")
t.expect(uikit:find('if style == "plain" and not foreground', 1, true) ~= nil, "UIKit plain buttons take the tint")
t.expect(uikit:find('props.background or "secondaryBackground"', 1, true) ~= nil,
	"UIKit GroupBox fills with the secondary background")

os.exit(t.summary() and 0 or 1)
