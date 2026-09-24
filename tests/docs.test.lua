_G.__headless = true
local t = require("TestKit")

-- Regression coverage for the generated component reference:
-- source --- docblocks in lua/embedded/AppKit.lua and their
-- generated Markdown in docs/reference/generated/.
local SRC = "lua/embedded/AppKit.lua"
local GENDIR = "docs/reference/generated/"
local PILOT = { "Button", "Text", "VStack" }

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local src = readFile(SRC)
t.expect(src ~= nil, "doc source exists: " .. SRC)

-- Collect --- docblocks attached to `function AppKit.<Name>(`.
local blocks = {} -- name -> { summary=string, props=n, examples=n, tag=string }
if src then
	local pending = {}
	local function flush(funcName)
		if #pending > 0 and funcName then
			local summary, tag, props, examples = "", nil, 0, 0
			for _, line in ipairs(pending) do
				if line:match("^@tag%s+") then
					tag = line:match("^@tag%s+(%S+)")
				elseif line:match("^@prop%s+") then
					props = props + 1
				elseif line:match("^@example%s+") then
					examples = examples + 1
				elseif summary == "" and line ~= "" and not line:match("^@") then
					summary = line
				end
			end
			blocks[funcName] = { summary = summary, tag = tag, props = props, examples = examples }
		end
		return {}
	end
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		local stripped = line:match("^%s*(.-)%s*$")
		local doc = stripped:match("^%-%-%-%s?(.*)$")
		if doc ~= nil then
			table.insert(pending, doc)
		elseif stripped == "" then
			-- Blank line ends the block unless more --- lines follow;
			-- simplified: keep pending (generator only skips blanks
			-- when followed by ---). Dangling blocks flush on next code.
		else
			local funcName = stripped:match("^function%s+AppKit%.([%w_]+)%s*%(")
			pending = flush(funcName)
		end
	end
end

for _, name in ipairs(PILOT) do
	local b = blocks[name]
	t.expect(b ~= nil, name .. " has a --- docblock in " .. SRC)
	if b then
		t.expect(b.tag == name, name .. " docblock carries @tag " .. name)
		t.expect(b.summary ~= "", name .. " docblock has a one-line summary")
		t.expect(b.props >= 1, name .. " docblock documents >= 1 @prop")
		t.expect(b.examples >= 1, name .. " docblock has >= 1 @example")
	end
end

-- Every @prop line in pilot blocks follows the generator contract:
-- `@prop <name> <type> required|optional. <description>`.
if src then
	for _, name in ipairs(PILOT) do
		local body = src:match("function%s+AppKit%." .. name .. "%s*%(")
		t.expect(body ~= nil, name .. " constructor still exists in " .. SRC)
	end
	local bad = 0
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		local doc = line:match("^%s*%-%-%-%s?(.*)$")
		if doc and doc:match("^@prop%s+") then
			local name, ptype, req, desc = doc:match("^@prop%s+(%S+)%s+(%S+)%s+(%S+)%s*(.-)%s*$")
			if not name or not ptype or (req ~= "required." and req ~= "optional.") or desc == "" then
				bad = bad + 1
				io.stderr:write("  malformed @prop: " .. doc .. "\n")
			end
		end
	end
	t.assertEqual(bad, 0, "all @prop lines match the generator contract")
end

-- Generated pages exist and carry the SwiftUI page shape.
local index = readFile(GENDIR .. "index.md")
t.expect(index ~= nil, "generated reference index exists")
for _, name in ipairs(PILOT) do
	local page = readFile(GENDIR .. name .. ".md")
	t.expect(page ~= nil, "generated page exists: " .. name .. ".md")
	if page then
		t.expect(page:find("# " .. name, 1, true) ~= nil, name .. ".md has a title")
		t.expect(page:find("GENERATED", 1, true) ~= nil, name .. ".md carries a generated marker")
		t.expect(page:find("## Overview", 1, true) ~= nil, name .. ".md has an Overview section")
		t.expect(page:find("## Example", 1, true) ~= nil, name .. ".md has an Example section")
		t.expect(page:find("<" .. name .. " ... />", 1, true) ~= nil,
			name .. ".md shows its XML tag declaration")
		t.expect(page:find(SRC, 1, true) ~= nil, name .. ".md links back to its Lua source")
	end
	if index then
		t.expect(index:find(name .. ".md", 1, true) ~= nil, "reference index links " .. name)
	end
end

-- MkDocs nav publishes the pilot pages.
local mkdocs = readFile("mkdocs.yml")
t.expect(mkdocs ~= nil, "mkdocs.yml exists")
if mkdocs then
	t.expect(mkdocs:find("Overview: reference/generated/index.md", 1, true) ~= nil,
		"mkdocs nav publishes the generated reference index")
end

os.exit(t.summary() and 0 or 1)
