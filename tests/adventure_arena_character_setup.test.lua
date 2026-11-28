_G.__headless = true

local t = require("TestKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Controller = require("apps.adventure-arena.controllers.SessionController")
local Store = require("apps.adventure-arena.Store")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local Words = require("apps.adventure-arena.services.Words")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local views = "apps/adventure-arena/views/"
local function contains(source, text) return source:find(text, 1, true) ~= nil end

for _, lang in ipairs({ "en", "de", "ru" }) do
	Store.new { language = lang }
	local words = Words.load(lang)
	local model = Session.new { engineFactory = function(game, seed)
		return ZILRuntime.new(game, nil, seed)
	end, newSeed = function() return 97 end }
	local id = "books." .. lang .. ".blackout-at-meridian"
	local actions, data, content, sheet, disposed, dismissed
	local function describe(template, values)
		values.resources = words
		local description = xml.describeFile(views .. template .. ".etlua", values)
		xml.validateActions(description)
		return description.source
	end
	local controller = Controller.new {
		model = model, resources = function() return words end, ns = {},
		push = function(_, details) error(details.message) end, back = function() end,
		renderTemplate = function(template, values)
			actions, sheet = values.actions, describe(template, values)
			return {}, { characterSetup = {} }
		end,
		mountTemplate = function()
			return {
				update = function(_, values)
					data = values
					content = describe("sections/CharacterSetup", values)
				end,
				dispose = function() disposed = true end,
			}
		end,
		presentSheet = function(view) return view end,
		dismissSheet = function() dismissed = true end,
	}
	-- Run the real controller open action, with native mounting replaced by
	-- the same XML description/action validation that the native mount uses.
	controller.openReader = function() return true end
	t.expect(controller:show(id, true), "the RPG opens its character chooser")
	t.assertEqual(#data.profiles, 3)
	t.assertEqual(data.hero, data.profiles[1], "preview the default preset immediately")
	t.expect(contains(sheet, "title=\"@heroContinue\""), "one Continue action confirms the selection")
	for _, profile in ipairs(data.profiles) do
		t.expect(contains(content, profile.portrait), "each card shows its portrait")
		t.expect(contains(content, profile.summary), "every description is visible before selection")
	end
	t.expect(not model.engine and not SavedGames:find(id), "opening a preview does not run GO or save")
	local first = data.hero
	actions.pick_2()
	t.assertEqual(data.hero, data.profiles[2])
	t.expect(data.hero.rows[1].value ~= first.rows[1].value, "browsing compares different preset values")
	t.expect(contains(content, words.heroSelected .. ". " .. data.hero.title), "selection follows the tapped card")
	actions.nameChanged(string.rep("a", 33))
	t.expect(not actions.confirm(), "invalid names do not start the story")
	t.expect(contains(content, words.heroNameError), "invalid names display a localized error")
	t.expect(actions.cancel() and disposed and dismissed, "cancel cleans up the preview")
	t.expect(not actions.confirm() and not model.engine and not SavedGames:find(id), "stale actions cannot start a cancelled setup")
	t.expect(controller:show(id, true))
	actions.pick_2()
	actions.nameChanged("Алёна")
	local selected = data.hero
	-- Verify both the preview and live sheet originate in the story rules.
	t.expect(actions.confirm(), "confirm starts the highlighted preset")
	t.assertEqual(SavedGames:find(id).setup.id, selected.id)
	t.assertEqual(model.moves, 0)
	local sheetData = model.engine:characterSheet()
	t.assertEqual(sheetData.name, "Алёна")
	for i, row in ipairs(selected.rows) do
		t.assertEqual(row.label, sheetData.rows[i].label)
		t.assertEqual(row.value, sheetData.rows[i].value)
		t.assertEqual(row.maximum, sheetData.rows[i].maximum)
		if row.group then t.assertEqual(row.group, sheetData.rows[i].group) end
		if row.rankLabel then t.assertEqual(row.rankLabel, sheetData.rows[i].rankLabel) end
	end

end

os.exit(t.summary() and 0 or 1)
