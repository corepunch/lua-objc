_G.__headless = true

local t = require("TestKit")

local path = "tests/parity/manifest.json"
local file = assert(io.open(path, "r"))
local manifest = file:read("*a")
file:close()

t.expect(manifest:match('"version"%s*:%s*1'), "parity manifest has version 1")
t.expect(manifest:match('"statusValues"'), "parity manifest declares status values")
t.expect(manifest:match('"cases"'), "parity manifest declares cases")

local expectedCases = {
	"text.single.default",
	"stack.h.spacing.default-text-spacer",
	"button.standard.action-counter",
}

for _, id in ipairs(expectedCases) do
	t.expect(manifest:find('"id": "' .. id .. '"', 1, true),
		"parity manifest includes " .. id)
	t.expect(manifest:find('"status"%s*:%s*"implemented%-unverified"'),
		"parity cases start unverified")
end

os.exit(t.summary() and 0 or 1)
