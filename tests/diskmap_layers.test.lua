-- Diskmap's folders mean what AGENTS.md says they mean. Each rule is checked
-- on the source: a file that breaks one is named.
--
--   helpers/   pure: computes over the rows and values it is given. It never
--              reaches for the store, a model, a service or a file.
--   models/    one table of the store each (`Model:extend`), stored or
--              computed. No AppKit, no service, no page.
--   flows/, pages/   no AppKit: a route answers data and runs actions.
--   AppKit     only the root controller, controllers/ and services/.
local t = require("TestKit")

local ROOT = "apps/diskmap/"

local function files(folder)
	local list = {}
	for path in io.popen("find " .. ROOT .. folder .. " -name '*.lua' 2>/dev/null"):lines() do table.insert(list, path) end
	table.sort(list)
	return list
end

-- The code of a file: its lines without comments.
local function code(path)
	local file = assert(io.open(path)); local text = file:read("*a"); file:close()
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if not line:match("^%s*%-%-") then table.insert(lines, line) end
	end
	return table.concat(lines, "\n")
end

local function refuses(folder, patterns)
	local list = files(folder)
	t.expect(#list > 0, folder .. " has files")
	for _, path in ipairs(list) do
		local text = code(path)
		for what, pattern in pairs(patterns) do
			t.expect(not text:find(pattern), path .. " does not " .. what)
		end
	end
end

local APPKIT = {["require AppKit"] = 'require%("AppKit"%)', ["call ns"] = "%f[%w_]ns%.[%a_]"}

refuses("helpers", {
	["read the bound store"] = "Model%.db",
	["require the model layer"] = 'require%("data%.model"%)',
	["require a model"] = 'require%("apps%.diskmap%.models%.',
	["require a service"] = 'require%("apps%.diskmap%.services%.',
	["require a flow"] = 'require%("apps%.diskmap%.flows%.',
	["require a page"] = 'require%("apps%.diskmap%.pages%.',
	["require the store's seed"] = 'require%("apps%.diskmap%.Store"%)',
	["open files"] = "%f[%w_]io%.[%a_]",
	["run commands"] = "os%.execute",
	["require AppKit"] = APPKIT["require AppKit"],
})

for _, path in ipairs(files("models")) do
	t.expect(code(path):find("Model:extend%(") ~= nil, path .. " is a table of the store (Model:extend)")
end
refuses("models", {
	["require a service"] = 'require%("apps%.diskmap%.services%.',
	["require a flow"] = 'require%("apps%.diskmap%.flows%.',
	["require a page"] = 'require%("apps%.diskmap%.pages%.',
	["require a controller"] = 'require%("apps%.diskmap%.controllers%.',
	["require AppKit"] = APPKIT["require AppKit"],
	["call ns"] = APPKIT["call ns"],
})

refuses("pages", APPKIT)
refuses("flows", APPKIT)

os.exit(t.summary() and 0 or 1)
