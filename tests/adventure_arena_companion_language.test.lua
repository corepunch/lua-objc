local t = require("TestKit")
local root = "apps/adventure-arena/zilscript"
local pwd = assert(io.popen("pwd"))
local interpreter = pwd:read("l") .. "/build/headless-lua"
pwd:close()
local function output(story)
	local pipe = assert(io.popen("cd " .. root .. " && " .. interpreter .. " main.lua --companion " .. story .. " </dev/null 2>&1"))
	local text = pipe:read("a")
	t.expect(pipe:close(), story .. " starts successfully")
	return text
end
for _, case in ipairs({
	{ "books.en.last-door-of-battleworld.last-door-of-battleworld", "What will you do?", "In this scene", "Choose a number" },
	{ "books.ru.last-door-of-battleworld.last-door-of-battleworld", "Что вы будете делать?", "Здесь", "Выберите номер или введите команду" },
	{ "books.de.blackout-at-meridian.blackout-at-meridian", "Was möchtest du tun?", "An diesem Ort", "Wähle eine Nummer" },
}) do
	local text = output(case[1])
	for index = 2, 4 do
		t.expect(text:find(case[index], 1, true) ~= nil, case[1] .. " displays " .. case[index])
	end
end
os.exit(t.summary() and 0 or 1)
