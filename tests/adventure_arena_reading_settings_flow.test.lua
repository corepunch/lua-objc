_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")

local button, slider, picker = ns.Button, ns.Slider, ns.Picker
local buttonActions, pickerControls, sliderControls = {}, {}, {}
ns.Button = function(props)
	local view = button(props)
	buttonActions[view] = props.action
	return view
end
ns.Slider = function(props)
	table.insert(sliderControls, { onChange = props.onChange, min = props.min, max = props.max })
	return slider(props)
end
ns.Picker = function(props)
	table.insert(pickerControls, { action = props.action, options = props.options })
	return picker(props)
end

local game = {
	id = "sanitarium",
	title = "Sanitarium",
	description = "A complete synopsis for the reading session.",
}
local engineState = {
	score = 2,
	moves = 3,
	maxScore = 10,
	room = "Sanitarium Gate",
}
local model = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function() return "The gate stands open." end,
			progress = function() return engineState end,
			roomName = function() return engineState.room end,
			exits = function() return { "north" } end,
		}, "The rusted gate stands open."
	end }
end })

local currentTemplate, sessionRefs, sheetRefs
local presentedSheet, presentedDetents, dismissedSheet
local controller = SessionController.new {
	model = model,
	findGame = function(id) return id == game.id and game or nil end,
	push = function(template, data)
		currentTemplate = template
		local view, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, ns)
		if template == "Session" then sessionRefs = refs end
		return view, refs
	end,
	back = function() end,
	ns = ns,
	readingSettings = ReadingSettings.new(),
	renderTemplate = function(template, data)
		currentTemplate = template
		local view, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, ns)
		sheetRefs = refs
		return view, refs
	end,
	presentSheet = function(sheet, detents)
		presentedSheet, presentedDetents = sheet, detents
		return sheet
	end,
	dismissSheet = function(sheet) dismissedSheet = sheet end,
}

t.expect(controller:show(game.id), "session screen opens for the selected game")
t.assertEqual(sessionRefs.sessionTitle.text, game.title, "session navigation title uses the game title")
t.assertEqual(sessionRefs.gameTitle.text, game.title, "session reading content starts with the game title")
t.assertEqual(sessionRefs.gameDescription.text, game.description, "session reading content includes the full synopsis")
t.assertEqual(sessionRefs.roomTitle.text, "Sanitarium Gate", "session content identifies the active room")
t.assertEqual(sessionRefs.progress.text, "Score 2/10 | Moves 3", "session header shows engine score and moves")

local openSettings = buttonActions[sessionRefs.readingSettings]
t.expect(type(openSettings) == "function", "reading settings button has a native action")
if openSettings then openSettings() end
t.assertEqual(currentTemplate, "ReadingSettings", "reading settings opens its etlua sheet")
t.expect(presentedSheet ~= nil, "reading settings sheet is presented")
t.assertEqual(table.concat(presentedDetents or {}, ","), "medium,large", "reading sheet supports medium and large detents")
t.assertEqual(#pickerControls, 2, "reading sheet renders native font and theme pickers")
t.assertEqual(table.concat(pickerControls[1].options, ","), "System,Serif,Rounded,Mono",
	"font picker matches the reading options")
t.assertEqual(table.concat(pickerControls[2].options, ","), "System,White,Sepia,Black",
	"theme picker matches the appearance options")
t.assertEqual(#sliderControls, 1, "reading sheet renders one font-size slider")
t.assertEqual(sliderControls[1].min, 14, "font-size slider uses the supported minimum")
t.assertEqual(sliderControls[1].max, 24, "font-size slider uses the supported maximum")
t.assertEqual(sheetRefs.sizeSlider.doubleValue, 17, "font-size slider starts at the reference default")

pickerControls[1].action(3)
t.assertEqual(controller.readingSettings:presentation().font, "monospaced", "font control updates reading preferences")
sliderControls[1].onChange(20.4)
t.assertEqual(controller.readingSettings:presentation().fontSize, 20, "font-size control rounds to a whole point")
t.assertEqual(sheetRefs.sizeValue.text, "20", "sheet displays the updated font size")
t.assertEqual(sheetRefs.sizeSlider.doubleValue, 20, "sheet slider tracks the chosen font size")
t.assertEqual(sheetRefs.previewBody.font.pointSize, 20, "preview applies the selected font size")
t.assertEqual(sessionRefs.output.font.pointSize, 20, "session transcript applies the selected font size")
t.assertEqual(sessionRefs.gameDescription.font.pointSize, 20, "session synopsis applies the selected font size")

pickerControls[2].action(2)
t.assertEqual(controller.readingSettings:presentation().theme, "sepia", "theme control updates reading preferences")
t.expect(math.abs(sheetRefs.preview.backgroundColor.redComponent - 245 / 255) < 0.01,
	"preview uses the sepia paper background")
t.expect(math.abs(sessionRefs.transcriptScroll.backgroundColor.redComponent - 245 / 255) < 0.01,
	"session reading surface uses the same sepia background")
t.assertEqual(sessionRefs.output.text, "The rusted gate stands open.",
	"changing reading preferences preserves the game transcript")
t.assertEqual(sessionRefs.progress.text, "Score 2/10 | Moves 3",
	"changing reading preferences preserves session progress")

local done = buttonActions[sheetRefs.done]
t.expect(type(done) == "function", "reading settings Done button has a native action")
if done then done() end
t.assertEqual(dismissedSheet, presentedSheet, "Done dismisses the presented settings sheet")
t.assertEqual(controller.readingSettingsRefs, nil, "closing the sheet releases its template refs")

ns.Button, ns.Slider, ns.Picker = button, slider, picker
os.exit(t.summary() and 0 or 1)
