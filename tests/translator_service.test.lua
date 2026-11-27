local t = require("TestKit")
local Translator = require("apps.translator.services.Translator")

-- The service, reading its files through a reader as it does on iOS.
local reads = {}
local diskOpen = io.open
local function readFile(path)
	table.insert(reads, path)
	local file = assert(diskOpen(path, "rb"))
	local body = file:read("a")
	file:close()
	return body
end
local engine = Translator.new({ readFile = readFile })
t.expect(not engine:isLoaded(), "the dictionaries are not loaded until the first translation")
t.assertEqual(engine:translate(" \n\t"), "", "empty input needs no assets")
t.expect(not engine:isLoaded() and #reads == 0, "empty input keeps the engine unloaded")
local translated, failure = engine:translate("She was here.")
t.assertEqual(translated, "Она была здесь.", "a sentence translates")
t.assertEqual(failure, nil, "successful diagnostics are not a page error")
t.expect(engine:isLoaded(), "the language data is loaded")
local dataPath = "apps/translator/en-ru-translator/dictionary/"
t.assertEqual(reads[1], dataPath .. "vocabulary.tsv", "read authored words through the platform reader")
t.assertEqual(reads[2], dataPath .. "assets.tsv", "read the bundled data manifest")
for _, path in ipairs(reads) do
	t.expect(path:sub(1, #dataPath) == dataPath and path:match("%.tsv$"), "read only new language data")
end
local initialReads = #reads
t.assertEqual(engine:translate("I fly home.\n\nThere was no answer."), "Я лечу домой.\n\nНе было ответа.",
	"each line translates alone and the breaks are kept")
t.assertEqual(engine:translate(""), "", "nothing translates to nothing")
t.assertEqual(engine:translate("Xyzzy."), "Xyzzy.", "an unknown word passes through")
for _, apostrophe in ipairs({ "'", "’", "‘" }) do
	t.assertEqual(engine:translate("I" .. apostrophe .. "m flying home."), "Я лечу домой.",
		"the contraction translates with straight or smart apostrophes")
end
local open, path = io.open, package.path
engine:translate("She was here.")
t.expect(io.open == open and package.path == path, "a call does not change global IO or module paths")
t.assertEqual(#reads, initialReads, "later sentences reuse parsed language data")
t.assertEqual(Translator.new({ readFile = false }):translate("I am home."), "Я дома.",
	"the service reads from disk without a reader")

-- Typing changes one line: the others come from the previous call.
local counting = Translator.new({ readFile = false })
counting.engine = { translate = function(line) counting.calls = (counting.calls or 0) + 1; return "<" .. line .. ">" end }
counting:translate("one\ntwo")
counting.calls = 0
t.assertEqual(counting:translate("one\ntwo!"), "<one>\n<two!>", "the text is translated line by line")
t.assertEqual(counting.calls, 1, "only the changed line goes to the engine")

-- Upstream throws for unsupported branches; the page receives a message.
counting.engine.translate = function() error("unsupported lexical branch", 0) end
local failedText, message = counting:translate("bad")
t.assertEqual(failedText, nil, "engine errors do not escape the service")
t.assertEqual(message, "unsupported lexical branch", "the error reaches the page")
t.expect(io.open == open and package.path == path, "a failed translation restores global IO and module paths")
t.assertEqual(counting.lines["one"], "<one>", "failure preserves the previous successful line cache")
local missing = Translator.new({ readFile = function() return nil, "missing asset" end })
failedText, message = missing:translate("I am home.")
t.expect(failedText == nil and message:find("vocabulary.tsv", 1, true) ~= nil, "missing assets are reported")
t.expect(not missing:isLoaded(), "a failed asset load can be retried")
t.expect(io.open == open and package.path == path, "a failed asset load restores global state")

os.exit(t.summary() and 0 or 1)
