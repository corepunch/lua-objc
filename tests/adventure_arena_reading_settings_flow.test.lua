_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local ReadingSettingsController = require("apps.adventure-arena.controllers.ReadingSettingsController")
local Template = require("ui.template")

local button, slider, picker, page, toggle = ns.Button, ns.Slider, ns.Picker, ns.Page, ns.Toggle
local buttonActions, pickerControls, sliderControls, toolbarActions, toggleControls = {}, {}, {}, {}, {}
-- Toolbar items belong to the Page, not the content tree; capture their actions.
ns.Page = function(props)
	for _, item in ipairs(props.toolbar or {}) do toolbarActions[item.id] = item.action end
	return page(props)
end
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
ns.Toggle = function(props)
	table.insert(toggleControls, { onChange = props.onChange })
	return toggle(props)
end

local game = {
	id = "sanitarium", title = "Sanitarium", shortDescription = "A psychological horror adventure.",
	description = "A complete synopsis for the reading session.",
	tint = "#047857", tintDark = "#6EE7B7", ink = "#047857|#6EE7B7", statusLine = nil,
}
local engineState = { score = 2, moves = 3, maxScore = 10, room = "Sanitarium Gate" }
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

local function mountTemplate(host, template)
	return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns)
end
local settings = ReadingSettings.new()
local saved
local controller
local options = ReadingSettingsController.new {
	model = settings,
	mountTemplate = mountTemplate,
	store = { save = function(value) saved = value end },
	onChange = function() controller:applyReadingSettings() end,
}

local sessionRefs, sheetRefs, presentedSheet, presentedDetents, dismissedSheet
controller = SessionController.new {
	model = model,
	findGame = function(id) return id == game.id and game or nil end,
	push = function(template, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, ns)
		if template == "Session" then sessionRefs = refs end
		return view, refs
	end,
	back = function() end,
	ns = ns,
	readingSettings = settings,
	readingOptions = options,
	renderTemplate = function(template, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, ns)
		sheetRefs = refs
		return view, refs
	end,
	mountTemplate = mountTemplate,
	presentSheet = function(sheet, detents)
		presentedSheet, presentedDetents = sheet, detents
		return sheet
	end,
	dismissSheet = function(sheet) dismissedSheet = sheet end,
}

t.expect(controller:show(game.id), "session screen opens for the selected game")
t.assertEqual(sessionRefs.sessionTitle.text, game.title, "the running head names the story")
t.assertEqual(sessionRefs.sessionPlace.text, "Chapter I · Sanitarium Gate", "the running head names the chapter and room")
local function page() return controller.transcript.refs end
t.assertEqual(page().gameTitle.text, game.title, "the page opens on the title")
t.assertEqual(page().gameDescription.text, game.shortDescription, "the tagline is the title page's epigraph")
t.assertEqual(page().sceneTitle_1.text, "Sanitarium Gate", "the first chapter identifies the active room")
t.assertEqual(sessionRefs.progress.text, "Score 2 of 10 · 3 moves", "the folio shows score and moves")
t.assertEqual(page().paragraph_1_1.font.pointSize, 18, "the story is set at the default 18pt")

local openSettings = toolbarActions.readingSettings
t.expect(type(openSettings) == "function", "the text-size toolbar item has an action")
if openSettings then openSettings() end
t.expect(presentedSheet ~= nil, "Themes & Settings is presented")
t.assertEqual(table.concat(presentedDetents or {}, ","), "medium,large", "the sheet supports medium and large detents")
local optionRefs = controller.readingSettingsOptions.refs
t.expect(optionRefs.theme_paper ~= nil and optionRefs.theme_night ~= nil, "themes are shown as page swatches")
t.assertEqual(#pickerControls, 2, "the sheet renders font and spacing pickers")
t.assertEqual(table.concat(pickerControls[1].options, ","), "Serif,Sans,Rounded,Mono", "font choices")
t.assertEqual(table.concat(pickerControls[2].options, ","), "Compact,Normal,Relaxed", "leading choices")
t.assertEqual(sliderControls[1].min, 14, "font-size slider uses the supported minimum")
t.assertEqual(sliderControls[1].max, 26, "font-size slider uses the supported maximum")
t.assertEqual(optionRefs.sizeSlider.value, 18, "the slider starts at the current size")
t.expect(optionRefs.previewBody == nil, "the sheet needs no sample page: the book is behind it")

sliderControls[1].onChange(20.4)
t.assertEqual(settings.fontSize, 20, "font-size control rounds to a whole point")
t.assertEqual(page().paragraph_1_1.font.pointSize, 20, "the open book re-sets its type")
t.assertEqual(saved.fontSize, 20, "the new size is persisted")
t.assertEqual(#pickerControls, 2, "dragging the slider leaves the panel in place")

pickerControls[1].action(1)
t.assertEqual(settings.font, "default", "font control updates reading preferences")
t.assertEqual(#pickerControls, 4, "a discrete choice re-renders the panel to show it")

buttonActions[controller.readingSettingsOptions.refs.theme_night]()
t.assertEqual(settings.theme, "night", "the Night swatch selects the night page")
t.expect(math.abs(sessionRefs.session.backgroundColor.redComponent) < 0.01, "the page turns black")
t.assertEqual(page().paragraph_1_1.text, "The rusted gate stands open.", "re-setting the page preserves the story")
t.assertEqual(sessionRefs.progress.text, "Score 2 of 10 · 3 moves", "re-setting the page preserves progress")
toggleControls[#toggleControls].onChange(true)
t.expect(settings.justified, "the justify toggle updates reading preferences")
t.assertEqual(page().paragraph_1_1.textAlignment, 3, "the open book is justified")

local done = buttonActions[sheetRefs.done]
t.expect(type(done) == "function", "Done has a native action")
if done then done() end
t.assertEqual(dismissedSheet, presentedSheet, "Done dismisses the presented settings sheet")
t.assertEqual(controller.readingSettingsRefs, nil, "closing the sheet releases its template refs")
t.assertEqual(#options.mounted, 0, "closing the sheet unmounts its options")

-- The Settings tab mounts the same options with a sample page.
local host = ns.VStack {}
local tab = options:mount(host, true)
t.expect(tab.refs.previewBody ~= nil and tab.refs.previewBody.dropCap, "the Settings tab shows a sample page with a drop cap")
t.assertEqual(tab.refs.previewBody.textAlignment, 3, "the sample page follows the preferences")

ns.Button, ns.Slider, ns.Picker, ns.Page, ns.Toggle = button, slider, picker, page, toggle
os.exit(t.summary() and 0 or 1)
