local t = require("TestKit")
local etlua = require("etlua")
local CharacterSheet = require("apps.adventure-arena.services.CharacterSheet")
local Words = require("apps.adventure-arena.services.Words")
local ReaderStatus = require("apps.adventure-arena.helpers.ReaderStatus")
local Controller = require("apps.adventure-arena.controllers.SessionController")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")

local fileOpen = io.open
local function read(path)
  local file, err = fileOpen(path, "rb")
  if not file then return nil, err end
  local data = file:read("a")
  file:close()
  return data
end
local template = assert(read("apps/adventure-arena/views/sheets/CharacterStatus.etlua"))
local book = { id = "books.ru.blackout-at-meridian", language = "ru", title = "Огни Меридиана",
  startFile = "blackout-at-meridian.zil", statusLine = "moves" }
local session = Session.new {
  engineFactory = function(game, seed) return Runtime.new(game, read, seed) end,
  newSeed = function() return 97 end,
}
local heading, opened, actions, onDismiss
local printError = { hidden = true }
local controller = setmetatable({
  model = session, game = book, reader = { isDisposed = function() return false end, update = function() end },
  readerData = function(self) return { reading = {}, canShowCharacterStatus = self.model.engine ~= nil } end,
  renderCompletions = function() end,
  heading = { update = function(_, data) heading = data.progress end },
  resources = function() return Words.load("ru") end,
  renderTemplate = function(name, data)
    t.assertEqual(name, "sheets/CharacterStatus")
    actions = data.actions
    opened = assert(etlua.render(template, data))
    return opened, { characterPrintError = printError }
  end,
  presentSheet = function(sheet, _, onClose) onDismiss = onClose; return sheet end,
  dismissSheet = function() end,
  ns = { printHTML = function(html) return html:find("85 / 90", 1, true) ~= nil end },
}, { __index = Controller })

t.expect(not controller:showCharacterStatus())
t.expect(session:start(book, nil, { id = "arc", name = "Алёна <Гром>" }, assert(session:prepare(book))))
controller:render()
t.assertEqual(heading, "Здоровье 90/90")
t.expect(session:submit("север"))
t.expect(session:submit("спасти трамвай"))
controller:render()
t.assertEqual(heading, "Здоровье 85/90")
local before = session:snapshot()
t.expect(controller:showCharacterStatus())
t.expect(opened:find("85 / 90", 1, true))
t.expect(opened:find("Алёна &lt;Гром&gt;", 1, true))
t.expect(opened:find("@hideCharacterMonitor", 1, true))
t.expect(not controller:showCharacterStatus(), "one status sheet at a time")
onDismiss()
t.expect(controller:showCharacterStatus(), "interactive dismissal allows reopening")
actions.monitor()
t.expect(heading ~= "Здоровье 85/90" and not controller.characterStatusSheet)
t.expect(controller:showCharacterStatus())
t.expect(opened:find("@showCharacterMonitor", 1, true))
actions.print()
t.expect(printError.hidden)
actions.monitor()
t.assertEqual(heading, "Здоровье 85/90")
t.assertEqual(session:snapshot().moves, before.moves)
t.assertEqual(#session:snapshot().commands, #before.commands)
t.assertEqual(ReaderStatus.monitor({ rows = { { label = "Composure", value = 38,
  maximum = 55, group = "resources" } } }), "Composure 38/55")
t.assertEqual(ReaderStatus.monitor({ rows = { { label = "Karma", value = 50, group = "resources" } } }), nil)
os.exit(t.summary() and 0 or 1)
