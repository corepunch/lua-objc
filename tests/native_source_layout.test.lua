_G.__headless = true

local t = require("TestKit")
local bridge = require("AppKitNative")

local function read(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end

-- Guard the folder contract without enumerating classes: adding a native
-- implementation must not bring back a separate header for every class.
local function checkFolder(path)
	local headers = {}
	local implementations = {}
	for _, entry in ipairs(assert(bridge._listDirectory(path))) do
		if entry.directory then
			checkFolder(entry.path)
		elseif entry.name:match("%.h$") then
			headers[#headers + 1] = entry.name
		elseif entry.name:match("%.m$") then
			implementations[#implementations + 1] = entry.path
		end
	end
	if #implementations == 0 then return end
	t.expect(#headers <= 1, path .. " has at most one shared native header")
	if path ~= "ios/LuaObjCHost" then return end
	t.assertEqual(#headers, 1, "independently compiled host files share one header")
	for _, implementation in ipairs(implementations) do
		local source = read(implementation)
		t.expect(source:find('#import "' .. headers[1] .. '"', 1, true) ~= nil,
			implementation .. " uses the shared host declarations")
		for imported in source:gmatch('#import%s+"([^"]+)"') do
			local file = io.open(path .. "/" .. imported, "r")
			t.expect(file ~= nil, implementation .. " imports an existing local file")
			if file then file:close() end
		end
	end

	-- Header-only edits must invalidate the executable, not just .m changes.
	local makefile = read("Makefile"):gsub("\\\n", " ")
	local dependencies = makefile:match("%$%(HOST_BINARY%):([^\n]+)") or ""
	t.expect(dependencies:find(path .. "/" .. headers[1], 1, true) ~= nil,
		"host executable tracks its shared header as a build dependency")
end

checkFolder("src")
checkFolder("ios")

os.exit(t.summary() and 0 or 1)
