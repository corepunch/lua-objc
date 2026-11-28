local t = require("TestKit")
local etlua = require("etlua")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")

local open = io.open
local function read(path)
  local file, err = open(path, "rb")
  if not file then return nil, err end
  local value = file:read("a")
  file:close()
  return value
end

local game = {
  id = "books.ru.blackout-at-meridian", language = "ru", startFile = "blackout-at-meridian.zil",
  title = "Огни Меридиана",
}
local function session()
  return Session.new {
    engineFactory = function(book, seed) return ZILRuntime.new(book, read, seed) end,
    newSeed = function() return 97 end,
  }
end

local reader = session()
local setup = assert(reader:prepare(game))
t.assertEqual(#setup.profiles, 3)
t.assertEqual(setup.profiles[3].id, "lens")
t.assertEqual(setup.profiles[2].title, "Искра")
t.assertEqual(setup.profiles[2].rows[9].value, 90)
t.expect(not reader.engine and not reader:snapshot(), "catalog inspection doesn't start the mission")

local component = assert(read("apps/adventure-arena/views/sections/CharacterSetup.etlua"))
local function ui(selected)
  return assert(etlua.render(component, {
    profiles = setup.profiles, selected = selected, name = "А <Б>",
    resources = { heroSelected = "Выбран" },
  }))
end
local initial = ui()
t.expect(initial:find('id="confirmHero".-disabled="true"'))
local selected = ui("arc")
t.expect(selected:find('id="confirmHero".-disabled="false"'))
t.expect(selected:find("А &lt;Б&gt;", 1, true))
t.expect(selected:find("Выбран: Искра", 1, true))

local ok, why = reader:start(game, nil, { id = "missing" }, setup)
t.expect(not ok and why == "invalid_preset" and not reader.engine)
ok, why = reader:start(game, nil, { id = "arc", name = ("Я"):rep(33) }, setup)
t.expect(not ok and why == "invalid_name" and not reader.engine)
local name = "Алёна <Гром> & дочь"
t.expect(reader:start(game, nil, { id = "arc", name = name }, setup))
local save = assert(reader:snapshot())
t.assertEqual(save.setup.id, "arc")
t.assertEqual(save.setup.name, name)
t.assertEqual(save.moves, 0)
t.assertEqual(#save.commands, 0)
t.assertEqual(reader.engine:characterSheet().name, name)
t.expect(reader:submit("север"))
t.expect(reader:submit("спасти трамвай"))
save = assert(reader:snapshot())

local restored = session()
t.expect(restored:start(game, save), "new saves restore the setup before replay")
t.assertEqual(restored.roomTitle, reader.roomTitle)
t.assertEqual(restored.moves, reader.moves)
t.assertEqual(restored.engine:characterSheet().rows[9].value, 85)
t.assertEqual(restored.engine:characterSheet().name, name)

local old = session()
t.expect(old:start(game, { seed = 97, commands = {"выбрать искру", "север"} }), "old saves replay their typed selection")
t.expect(not old.engine:requiresSetup() and old.engine:canExportSheet())
t.expect(old:snapshot().setup == nil)

local plain = assert(reader:prepare {
  id = "books.en.wondertown", startFile = "wondertown.zil", language = "en", title = "Wondertown",
})
t.assertEqual(#plain.profiles, 0, "books without a preset catalog don't get a character picker")
local UI = require("apps.adventure-arena.controllers.SessionController")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local uiModel = session()
local calls = { opens = 0, saves = 0, dismisses = 0 }
local originalRecord = SavedGames.record
SavedGames.record = function(_, snapshot)
  calls.saves = calls.saves + 1
  t.assertEqual(snapshot.setup.id, "lens")
  t.assertEqual(#snapshot.commands, 0)
end
local callbacks
local controller = setmetatable({
  model = uiModel,
  renderTemplate = function(_, data) callbacks = data.actions; return "sheet", { characterSetup = {} } end,
  mountTemplate = function() return { update = function() end, dispose = function() end } end,
  presentSheet = function(sheet) return sheet end,
  dismissSheet = function() calls.dismisses = calls.dismisses + 1 end,
  openReader = function() calls.opens = calls.opens + 1; return true end,
}, { __index = UI })
t.expect(controller:showCharacterSetup(game, assert(uiModel:prepare(game))))
local cancelled = callbacks
cancelled.pick_1()
cancelled.cancel()
t.expect(not cancelled.confirm() and not uiModel.engine)
t.assertEqual(calls.saves, 0)
t.expect(controller:showCharacterSetup(game, assert(uiModel:prepare(game))))
t.expect(not callbacks.confirm(), "selection is required before starting")
callbacks.pick_1()
callbacks.pick_3()
t.expect(not uiModel.engine, "previewing a different hero doesn't run the game")
t.expect(callbacks.confirm())
t.expect(not callbacks.confirm(), "confirming twice cannot start the mission twice")
t.assertEqual(calls.opens, 1)
t.assertEqual(calls.saves, 1)
t.assertEqual(calls.dismisses, 2)
SavedGames.record = originalRecord

os.exit(t.summary() and 0 or 1)
