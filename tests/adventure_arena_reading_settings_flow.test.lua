_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local Store = require("apps.adventure-arena.Store")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local ReadingSettingsController = require("apps.adventure-arena.controllers.ReadingSettingsController")
local Template = require("ui.template")
local Words = require("apps.adventure-arena.services.Words")
local function resources() return Words.load("en") end

local button, slider, picker, page, toggle = ns.Button, ns.Slider, ns.Picker, ns.Page, ns.Toggle
local paragraph = ns.Paragraph
local buttonActions, pickerControls, sliderControls, toolbarActions, toggleControls = {}, {}, {}, {}, {}
local proseColors
ns.Paragraph = function(props)
	if props[1] == "The rusted gate stands open." then
		proseColors = { body = props.color }
	end
	return paragraph(props)
end
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
	table.insert(toggleControls, { onChange = props.onChange, label = props.label or props.title or props[1] })
	return toggle(props)
end
-- The panel re-renders as preferences change; the newest toggle is live.
local function toggleNamed(label)
	for index = #toggleControls, 1, -1 do
		if toggleControls[index].label == label then return toggleControls[index] end
	end
end

local game = {
	id = "sanitarium", title = "Sanitarium", shortDescription = "A psychological horror adventure.",
	description = "A complete synopsis for the reading session.",
}
local engineState = { score = 2, moves = 3, maxScore = 10, room = "Sanitarium Gate" }
local model = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function() return "The gate stands open." end,
			progress = function() return engineState end,
			roomName = function() return engineState.room end,
			exits = function() return { "north" } end,
		}, "Blackwood Sanitarium\nStudio Null, 2024\nRelease 1\n\nSanitarium Gate\nThe rusted gate stands open."
	end }
end })

local function mountTemplate(host, template)
	return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns, resources)
end
local saved
Store.new { games = { game }, documents = { reading = { save = function(value) saved = value end } } }
local settings = ReadingSettings:current()
local controller
local options = ReadingSettingsController.new {
	mountTemplate = mountTemplate,
	onChange = function() controller:applyReadingSettings() end,
}

local sessionRefs, sheetRefs, presentedSheet, presentedDetents, dismissedSheet
controller = SessionController.new { resources = resources,
	model = model,
	push = function(template, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, ns)
		if template == "pages/Session" then sessionRefs = refs end
		return view, refs
	end,
	back = function() end,
	ns = ns,
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
t.assertEqual(controller.heading.refs.sessionTitle.text, "Sanitarium Gate", "the running head names the room")
local function page() return controller.transcript.refs end
t.assertEqual(page().bannerTitle_1.text, "Blackwood Sanitarium", "the title comes from the game")
t.assertEqual(page().bannerTitle_1.font.pointSize, 30, "the story's title is larger than the prose")
t.assertEqual(page().bannerLine_1_1.text, "Studio Null, 2024", "the game supplies its credits")
t.assertEqual(page().bannerLine_1_1.font.pointSize, 14, "credits use a smaller size")
t.assertEqual(page().bannerLine_1_2.text, "Release 1", "release follows the credits")
t.expect(proseColors and proseColors.body == settings:presentation().primaryTextColor, "ordinary prose uses the page ink")
t.expect(page().synopsis == nil, "the catalog synopsis stays outside the reader")
t.assertEqual(page().sceneTitle_2.text, "Sanitarium Gate", "the first scene identifies the active room")
t.assertEqual(controller.heading.refs.sessionScore.text, "Score 2 of 10", "the running head shows only the score")
t.assertEqual(page().paragraph_2_1.font.pointSize, 18, "the story is set at the default 18pt")

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
t.assertEqual(page().paragraph_2_1.font.pointSize, 20, "the open book re-sets its type")
t.assertEqual(page().bannerTitle_1.font.pointSize, 32, "the banner scales with reading size")
t.assertEqual(saved.fontSize, 20, "the new size is persisted")
t.assertEqual(#pickerControls, 2, "dragging the slider leaves the panel in place")

controller:submitCommand("look")
for _, choice in ipairs({ { 0, "serif" }, { 1, "default" }, { 2, "rounded" }, { 3, "monospaced" } }) do
	pickerControls[1].action(choice[1])
	local font = choice[2]
	local title = ns.Text { "title", size = 32, design = font, weight = "bold" }
	local scene = ns.Text { "scene", size = 29, design = font, weight = "semibold" }
	local command = ns.Text { "look", size = 19, design = font, weight = "medium" }
	local body = ns.Text { "body", size = 20, design = font }
	t.assertEqual(page().bannerTitle_1.font.fontName, title.font.fontName, font .. " book title follows the choice")
	t.assertEqual(page().sceneTitle_2.font.fontName, scene.font.fontName, font .. " scene title follows the choice")
	t.assertEqual(page().command_3.font.fontName, command.font.fontName, font .. " command follows the choice")
	t.assertEqual(page().paragraph_2_1.font.fontName, body.font.fontName, font .. " body follows the choice")
	t.assertEqual(controller.refs.input.font.fontName, body.font.fontName, font .. " command field follows the choice")
end
pickerControls[1].action(1)
t.assertEqual(settings.font, "default", "font control updates reading preferences")
t.assertEqual(#pickerControls, 2, "a discrete choice updates the panel's pickers in place")
t.assertEqual(controller.readingSettingsOptions.refs.fontPicker.selectedSegment, 1, "the font picker shows the new choice")

buttonActions[controller.readingSettingsOptions.refs.theme_night]()
t.assertEqual(settings.theme, "night", "the Night swatch selects the night page")
t.expect(proseColors and proseColors.body == settings:presentation().primaryTextColor, "ordinary prose follows the page ink after changing themes")
t.expect(math.abs(controller.refs.session.backgroundColor.redComponent) < 0.01, "the page turns black")
t.assertEqual(controller.refs.session.colorScheme, "dark", "a Night page is dark whatever the system says")
t.assertEqual(controller.heading.refs.sessionTitle.superview.colorScheme, "dark", "and so is its running head")
t.assertEqual(page().paragraph_2_1.text, "The rusted gate stands open.", "re-setting the page preserves the story")
t.assertEqual(controller.heading.refs.sessionScore.text, "Score 2 of 10", "re-setting the page preserves the score")
toggleNamed("Justify Text").onChange(true)
t.expect(settings.justified, "the justify toggle updates reading preferences")
t.assertEqual(page().paragraph_2_1.textAlignment, 3, "the open book is justified")

-- Reading preferences preserve the complete prose and its full column.
t.expect(controller.readingSettingsOptions.refs.dropCapToggle == nil, "the sheet offers no drop cap toggle")
t.assertEqual(#page().paragraph_2_1.textContainer.exclusionPaths, 0, "reading preferences leave prose at the margin")
t.assertEqual(page().paragraph_2_1.text, "The rusted gate stands open.", "the paragraph keeps its first letter")

local done = buttonActions[sheetRefs.done]
t.expect(type(done) == "function", "Done has a native action")
if done then done() end
t.assertEqual(dismissedSheet, presentedSheet, "Done dismisses the presented settings sheet")
t.assertEqual(controller.readingSettingsRefs, nil, "closing the sheet releases its template refs")
t.assertEqual(#options.mounted, 0, "closing the sheet unmounts its options")

-- The Settings tab mounts the same options with a sample page.
local host = ns.VStack {}
local tab = options:mount(host, true)
t.expect(tab.refs.previewBody ~= nil, "the Settings tab shows a sample page")
t.expect(tab.refs.chapter == nil, "the sample page has no chapter line")
t.assertEqual(tab.refs.previewBody.textAlignment, 3, "the sample page follows the preferences")

engineState.score, engineState.moves, engineState.room = 3, 4, "Courtyard"
controller:submitCommand("look")
t.assertEqual(controller.heading.refs.sessionTitle.text, "Courtyard", "a command refreshes the room title")
t.assertEqual(controller.heading.refs.sessionScore.text, "Score 3 of 10", "a command refreshes the toolbar score")

ns.Button, ns.Slider, ns.Picker, ns.Page, ns.Toggle = button, slider, picker, page, toggle
ns.Paragraph = paragraph
os.exit(t.summary() and 0 or 1)
