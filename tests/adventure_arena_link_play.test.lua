_G.__headless = true
local t = require("TestKit")
local base = "apps/adventure-arena/zilscript/"
package.path = base .. "?.lua;" .. base .. "?/init.lua;" .. package.path
local runtime = require("zilscript.runtime")
local play = require("zilscript.link_play")
local parser = require("zilscript.parser")
local compiler = require("zilscript.compiler")

local compiled = compiler.compile(parser.parse([[
<DEFMAC LIT? ('OBJ)
 <FORM AND <FORM FSET? .OBJ ',FLAMEBIT> <FORM FSET? .OBJ ',ONBIT>>>
<ROUTINE TEST-ACTIONS ()
 <COND (<VERB? EXAMINE OPEN CLOSE THROUGH> <LIT? ,PRSI>)>>
]]))
t.expect(compiled.combined:find("FSETQ(PRSI, FLAMEBIT)", 1, true), "macro FORM keeps its quoted global flame flag")
t.expect(compiled.combined:find("FSETQ(PRSI, ONBIT)", 1, true), "macro FORM keeps its second flag")
for _, verb in ipairs({ "EXAMINE", "OPEN", "CLOSE", "THROUGH" }) do
	t.expect(compiled.combined:find("'" .. verb .. "'", 1, true), "menu metadata retains action " .. verb)
end

local save = os.tmpname()
local last, lastEnv, activeGame
local function contents(path)
	local file = assert(io.open(path, "rb"))
	local body = file:read("*a")
	file:close()
	return body
end
local function invoke(args, reuse)
	local env = reuse and lastEnv or runtime.create_game_env()
	if not reuse then
		assert(runtime.init(env, true))
		env.require("zilscript")
		package.zilpath = base .. "books/wondertown/?.zil;" .. base .. "infocom/zork1/?.zil;" .. base .. "?.zil"
		env.PROSE_LINKS = true
		assert(runtime.load_modules(env, { "books.wondertown.wondertown" }, { silent = true }))
	end
	local restored = not args.new_game
	if restored and not reuse then assert(env.RESTORE(save)) end
	local game = reuse and activeGame or runtime.create_game(env, true)
	local function start()
		if reuse then return "" end
		_G._LLM_RESTORED = restored or nil
		local output = game:start()
		_G._LLM_RESTORED = nil
		return output
	end
	local result = play.run {
		args = args, env = env, game = game, gameName = "wondertown", restored = restored,
		savefile = save, start = start, act = function(command) return game:resume(command) end,
		room = function() return env.GETP(env.HERE, env.PQDESC) end,
	}
	last, lastEnv, activeGame = result, env, game
	return result
end
local function choose(test)
	local index = 0
	for _, command, target in last:gmatch('%["(.-)","(.-)","(.-)"%]') do
		index = index + 1
		if test(command, target) then return invoke({ choose = tostring(index) }, true) end
	end
	error("Expected player action missing: " .. last)
end
local function command(verb, noun)
	return function(value) return value:match("^" .. verb .. " ") and value:find(noun, 1, true) end
end

local opening = invoke { new_game = true, seed = 97 }
t.expect(opening:find('"room":"Workshop Floor"', 1, true), "debug opens the real reader scene")
t.expect(not opening:match('"take [^"]-can"'), "menus do not reveal the hidden oil can")
local before = contents(save)
local observed = invoke {}
t.assertEqual(contents(save), before, "observing links does not change the saved VM")
t.assertEqual(opening:match('"actions":(.*)'), observed:match('"actions":(.*)'), "fresh-process restore preserves exact numbered menu order")

local revealed = choose(function(value, target) return value:match("^examine ") and target == "workbench" end)
t.expect(revealed:match('"take [^"]-can"'), "examining the hiding place makes its actual object actionable")
choose(command("take", "string"))
local inventory = choose(function(value) return value == "inventory" end)
t.expect(inventory:find('"drop ', 1, true), "a carried object offers drop")
t.expect(contents(save .. ".transcript"):find("[[frayed string", 1, true), "native inventory names are actual prose links")
choose(function(value) return value == "north" end)
local carried = choose(function(value) return value == "inventory" end)
t.expect(carried:find("string", 1, true), "inventory links survive moving to another room and restoring")
choose(command("drop", "string"))
t.assertEqual(lastEnv.LOC(lastEnv.KEY_STRING), lastEnv.HERE, "selected menu action mutates the one actual string object")

-- The private generator lives in scalar VM state, not a host closure.
local randomState = lastEnv.PLAY_RANDOM
lastEnv.math.random(1, 100)
local advanced = lastEnv.PLAY_RANDOM
t.expect(advanced ~= randomState, "random generation advances saved VM state")
assert(lastEnv.SAVE(save))
invoke {}
t.assertEqual(lastEnv.PLAY_RANDOM, advanced, "restoring a snapshot does not reset its random sequence")

local original = contents(save)
local ok = pcall(invoke, { choose = "999999" }, true)
t.expect(not ok, "debug rejects actions outside the visible menu")
t.assertEqual(contents(save), original, "an invalid choice leaves the checkpoint untouched")
local previousGame = lastEnv.PLAY_GAME
lastEnv.PLAY_GAME = "other-story"
assert(lastEnv.SAVE(save))
t.expect(not pcall(invoke, {}, true), "debug refuses a snapshot belonging to another story")
lastEnv.PLAY_GAME = previousGame

local adjective = lastEnv.VOC("oil", lastEnv.ADJECTIVE)
lastEnv.SYNTAX { VERB = "OIL", ACTION = "V_EXAMINE", OBJECT = {} }
lastEnv.SYNTAX { VERB = "OIL", ACTION = "V_EXAMINE", OBJECT = {} }
t.assertEqual(lastEnv.WTQ(lastEnv.WQOIL, lastEnv.PSQADJECTIVE, lastEnv.P1QADJECTIVE), adjective,
	"re-registering a verb keeps the adjective meaning of the same word")
local gold = lastEnv.VOC("gold", lastEnv.ADJECTIVE)
lastEnv.VOC("gold", lastEnv.NOUN)
t.expect(lastEnv.ZIL_TRUE(lastEnv.WTQ(lastEnv.WQGOLD, lastEnv.PSQOBJECT, lastEnv.P1QOBJECT)),
	"a word that is both adjective and noun retains its noun marker")
t.assertEqual(lastEnv.WTQ(lastEnv.WQGOLD, lastEnv.PSQADJECTIVE, lastEnv.P1QADJECTIVE), gold,
	"adding a noun preserves the existing adjective")

-- FINISH yields its native ending prompt. Its lifecycle marker must still
-- prevent a fresh debug invocation from re-entering ordinary MAIN-LOOP.
local ending = coroutine.create(function()
	local ok, signal = pcall(lastEnv.JIGS_UP, "A test ending.")
	return not ok and lastEnv.IS_ZIL_CONTROL_SIGNAL(signal, "quit")
end)
local endedOK, quit = coroutine.resume(ending)
t.expect(endedOK and quit, "the link reader finishes through the native quit signal without parser prompts")
assert(lastEnv.SAVE(save))
local finished = invoke {}
t.expect(finished:find('"running":false', 1, true), "an ended VM remains ended after restore")
t.expect(finished:find('"actions":[]', 1, true), "ending snapshots expose no normal play actions")

os.remove(save)
os.remove(save .. ".transcript")
os.remove(save .. ".next")
os.exit(t.summary() and 0 or 1)
