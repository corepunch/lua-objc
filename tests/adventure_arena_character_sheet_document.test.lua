local t = require("TestKit")
local CharacterSheet = require("apps.adventure-arena.services.CharacterSheet")

local Portrait = require("apps.adventure-arena.services.Portrait")

local function contains(s, part)
	return s:find(part, 1, true) ~= nil
end

local dossier = {
	language = "ru", title = "Огни Меридиана", profile = "Искра", name = [[Алёна <Гром> & "Свет"]],
	rows = {
		{ label = "Ловкость", value = 30, group = "abilities", rankLabel = "Особый <ранг>" },
		{ label = "Интуиция", value = 20, group = "abilities" },
		{ label = "Мощь & скорость", value = 40, group = "powers" },
		{ label = "Здоровье", value = 85, maximum = 90, group = "resources" },
		{ label = "Карма", value = 50, group = "resources" },
	},
}
local document = CharacterSheet.document(dossier)
t.expect(contains(document, '<html lang="ru">'))
t.expect(contains(document, "Алёна &lt;Гром&gt; &amp; &quot;Свет&quot;"), "hero name is escaped")
t.expect(contains(document, "Мощь &amp; скорость"), "attribute labels are escaped")
t.expect(contains(document, "Особый &lt;ранг&gt;"), "rank labels are escaped")
t.expect(contains(document, 'id="abilities"') and contains(document, 'id="powers"') and contains(document, 'id="resources"'))
t.expect(contains(document, "85 / 90"), "current and maximum remain distinct")
t.expect(contains(document, "<dd>50</dd>"), "a resource without a maximum shows only the tracked number")
t.expect(contains(document, "Эти поля не заполняются из игры.") and contains(document, "Таланты и снаряжение"))
t.expect(contains(document, "size: auto") and contains(document, "@media print"), "uses the selected printer paper")
t.expect(not contains(document, "<Гром>"))
t.expect(not contains(document, "http://") and not contains(document, "https://"), "HTML works offline")

local generic = CharacterSheet.document({
	language = "de", title = "Die Höhle", profile = "Wanderer", name = "Frieda",
	rows = {{ label = "Ausdauer", value = 6, group = "custom" }, { label = "Focus", value = 3 }},
})
t.expect(contains(generic, '<html lang="de">') and contains(generic, "Charakterbogen"))
t.expect(contains(generic, 'id="stats"') and contains(generic, "Ausdauer") and contains(generic, "Focus"))
t.expect(not contains(generic, 'id="abilities"') and not contains(generic, 'id="powers"'))
t.expect(not contains(generic, "Talente &amp; Ausrüstung"), "generic systems get general notes only")
t.expect(not contains(generic, 'scope="col">Rang'), "omit the rank column if no row exposes a rank")

local templatePath, rendered, title
t.expect(CharacterSheet.print({
	_readFile = function(path)
		templatePath = path
		local file = assert(io.open(path, "rb"))
		local body = file:read("a")
		file:close()
		return body
	end,
	printHTML = function(html, jobTitle)
		rendered, title = html, jobTitle
		return true
	end,
}, dossier), "the native print bridge gets HTML read from the virtual file reader")
t.expect(contains(templatePath, "/views/exports/CharacterSheet.etlua"))
t.assertEqual(title, 'Лист персонажа: Алёна <Гром> & "Свет"')
t.assertEqual(rendered, document)
t.expect(not contains(rendered, "window.print"), "print content has no browser controls")
local function noFallback() error("the print action cannot share or open HTML") end
t.assertEqual(CharacterSheet.print({
	shareFiles = noFallback, openPath = noFallback,
}, dossier), false, "without a native print dialog the action fails cleanly")
t.assertEqual(CharacterSheet.print({
	printHTML = function() return false end, shareFiles = noFallback, openPath = noFallback,
}, dossier), false, "a failed print dialog never falls back to a share/browser")

t.expect(not contains(document, '<figure class="portrait">'), "no portrait means full width without a placeholder")
local imagePath = assert(Portrait.reference("books/en/example-adventure", "custom-hero"))
t.assertEqual(imagePath, "apps/adventure-arena/zilscript/books/en/example-adventure/portraits/custom-hero.png")
local fixture = "\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR\0\0\0\x01\0\0\0\x02\x08\0\0\0\0\xbc\xea\xe9\xfb"
	.. "\0\0\0\x0cIDAT\x78\x9c\x63\xe0\x62\x62\0\0\0\x26\0\x0d\x77\x87\xf0\xeb\0\0\0\0IEND\xae\x42\x60\x82"
local expectedURI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAAAAAC86un7AAAADElEQVR4nGPgYmIAAAAmAA13h/DrAAAAAElFTkSuQmCC"
local function virtualReader(bytes)
	return function(path)
		if path == imagePath then
			return bytes
		end
		local file = assert(io.open(path, "rb"))
		local body = file:read("a")
		file:close()
		return body
	end
end
dossier.portrait = imagePath
local illustrated = CharacterSheet.document(dossier, virtualReader(fixture))
t.expect(CharacterSheet.print({
	_readFile = virtualReader(fixture),
	printHTML = function(html)
		t.assertEqual(html, illustrated, "native print includes the optional embedded portrait")
		return true
	end,
}, dossier))
t.expect(contains(illustrated, 'src="' .. expectedURI .. '"'), "embeds exact binary PNG as an offline asset")
t.expect(contains(illustrated, 'alt="Портрет: Алёна &lt;Гром&gt; &amp; &quot;Свет&quot;"'), "localized alt text is safely escaped")
t.expect(contains(illustrated, 'class="portrait-stats"') and contains(illustrated, 'id="notes"'))
t.expect(not contains(illustrated, imagePath), "does not leave a bundle-relative image link")
t.assertEqual(CharacterSheet.document(dossier, virtualReader(nil)), document, "missing asset uses the original layout")
t.assertEqual(CharacterSheet.document(dossier, virtualReader("<svg/>")), document, "rejects non-PNG files")
t.assertEqual(CharacterSheet.document(dossier, virtualReader(fixture:sub(1, -2))), document, "rejects truncated PNGs")
t.assertEqual(CharacterSheet.document(dossier, virtualReader(fixture:sub(1, 33) .. fixture:sub(-12))), document, "missing image data uses the configuration without artwork")
local oversized = fixture:sub(1, 16) .. string.pack(">I4", 2049) .. fixture:sub(21)
t.assertEqual(CharacterSheet.document(dossier, virtualReader(oversized)), document, "rejects unreasonable image dimensions")
t.assertEqual(CharacterSheet.document(dossier, virtualReader(string.rep("a", 1024 * 1024 + 1))), document, "rejects oversized files")

for _, slug in ipairs({ "../secret", "arc.png", "/arc", "ARc", "a\nb", string.rep("a", 65) }) do
	t.assertEqual(Portrait.reference("books/en/example-adventure", slug), nil, "rejects a non-slug portrait ID")
end
t.assertEqual(Portrait.reference("books/en/../example-adventure", "arc"), nil)
t.assertEqual(Portrait.reference("https://test.invalid/books/en/example-adventure", "arc"), nil)
local forged = "apps/adventure-arena/zilscript/books/en/example-adventure/portraits/../../../private.png"
local attempted = false
t.assertEqual(Portrait.dataURI(forged, function() attempted = true end), nil)
t.expect(not attempted, "invalid references never reach the asset reader")
t.assertEqual(Portrait.dataURI(imagePath, function() error("unavailable") end), nil, "asset reader errors are optional")

os.exit(t.summary() and 0 or 1)
