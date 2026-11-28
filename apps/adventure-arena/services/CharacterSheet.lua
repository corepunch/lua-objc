local CharacterSheet = {}

local printTitle = { en = "Print", de = "Drucken", ru = "Печать" }

local escapes = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }
local function html(value)
	return (tostring(value or ""):gsub("[&<>\"']", escapes))
end

function CharacterSheet.document(sheet)
	local rows = {}
	for _, row in ipairs(sheet.rows) do
		local value = row.maximum and string.format("%d / %d", row.value, row.maximum) or tostring(row.value)
		table.insert(rows, string.format("<div><dt>%s</dt><dd>%s</dd></div>", html(row.label), html(value)))
	end
	return ([[<!doctype html>
<html lang="%s">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<style>
:root { color-scheme: light; color: #191713; background: #fff; }
body { max-width: 45rem; margin: 2rem auto; padding: 0 1.25rem; font: 1rem/1.5 system-ui, sans-serif; }
header { border-top: .6rem solid #171717; border-bottom: 2px solid #171717; padding: 1rem 0; }
p { margin: 0; }
.kicker { font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }
h1 { font: 700 clamp(2.25rem, 9vw, 4rem)/1 Georgia, serif; margin: .35em 0 .15em; overflow-wrap: anywhere; }
.profile { color: #3d3934; }
dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr)); gap: 0 1.75rem; }
dl div { display: flex; justify-content: space-between; gap: .5rem; align-items: baseline; border-bottom: 1px solid #a29b90; padding: .5em 0; break-inside: avoid; }
dt { font-weight: 600; }
button { margin: 1.25rem 0; font: inherit; padding: .4rem 1rem; }
dd { margin: 0; font-weight: 700; font-variant-numeric: tabular-nums; white-space: nowrap; }
@page { margin: 15mm; }
@media print { body { margin: 0; padding: 0; } dl { grid-template-columns: repeat(2, 1fr); } button { display: none; } }
</style>
</head>
<body>
<header><p class="kicker">%s</p><h1>%s</h1><p class="profile">%s</p></header>
<dl>%s</dl>
<button type="button" onclick="window.print()">%s</button>
</body>
</html>
]]):format(html(sheet.language), html(sheet.title), html(sheet.title), html(sheet.name), html(sheet.profile), table.concat(rows, "\n"), printTitle[sheet.language] or printTitle.en)
end

function CharacterSheet.share(ns, sheet)
	local document = CharacterSheet.document(sheet)
	if ns.shareFiles then
		return ns.shareFiles({ { name = "character-sheet.html", text = document } }, "CharacterSheet")
	end
	local temporary = os.tmpname()
	os.remove(temporary)
	local path = temporary .. ".html"
	local file, err = io.open(path, "wb")
	if not file then return false, err end
	local written, writeError = file:write(document)
	local closed, closeError = file:close()
	if not written or not closed then
		os.remove(path)
		return false, writeError or closeError
	end
	return ns.openPath(path)
end

return CharacterSheet
