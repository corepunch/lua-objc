_G.__headless = true

local t = require("TestKit")
local xml = require("ui.xml")
local Controller = require("apps.adventure-arena.controllers.SessionController")
local Words = require("apps.adventure-arena.services.Words")

local sheet = {
	language = "ru", title = "Огни Меридиана", profile = "Искра", name = "Алёна",
	rows = {
		{ label = "Здоровье", value = 85, maximum = 90, group = "resources" },
		{ label = "Карма", value = 50, group = "resources" },
	},
}
local prints, callbacks, sheetReads, errors = 0, nil, 0, { hidden = true }
local function unexpected() error("printing must never open an external app or share a file") end
local ns = {
	printHTML = function(html, title)
		prints = prints + 1
		t.assertEqual(title, "Лист персонажа: Алёна")
		t.expect(html:find("86 / 90", 1, true), "printing reads the latest stats, not the displayed snapshot")
		return true
	end,
	openPath = unexpected, shareFiles = unexpected,
}
local words = Words.load("ru")
local controller = Controller.new {
	model = { engine = { characterSheet = function()
		sheetReads = sheetReads + 1
		return sheet
	end } },
	ns = ns, resources = function() return words end,
	push = unexpected, back = unexpected, mountTemplate = unexpected,
	renderTemplate = function(template, values)
		t.assertEqual(template, "sheets/CharacterStatus")
		callbacks = values.actions
		-- Mirror the app's rendering boundary: status rows must not overwrite
		-- the localized resources table used by @done and other buttons.
		local withWords = { resources = words }
		for key, value in pairs(values) do withWords[key] = value end
		local description = xml.describeFile("apps/adventure-arena/views/" .. template .. ".etlua", withWords)
		xml.validateActions(description)
		t.expect(description.source:find("85 / 90", 1, true))
		t.expect(description.source:find('text="@sheetPrintFailed"', 1, true))
		return {}, { characterPrintError = errors }
	end,
	presentSheet = function(view) return view end,
	dismissSheet = function() end,
}

t.expect(controller:showCharacterStatus())
t.assertEqual(sheetReads, 1)
t.assertEqual(prints, 0)
sheet.rows[1].value = 86
t.expect(callbacks.print(), "pressing Print calls the native dialog from the status sheet")
t.assertEqual(prints, 1)
t.assertEqual(sheetReads, 2)
t.expect(errors.hidden, "no error on success")
ns.printHTML = function() return false end
t.expect(not callbacks.print() and not errors.hidden, "native refusal shows the localized error")
ns.printHTML = function() error("unavailable") end
t.expect(not callbacks.print() and not errors.hidden, "native failure stays in the modal")
callbacks.done()
t.expect(not callbacks.print() and prints == 1, "dismissed sheet cannot start printing")

os.exit(t.summary() and 0 or 1)
