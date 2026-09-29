-- Menu and button contracts shared by make test (AppKit) and the UIKit batch
-- host. Each platform is inspected through its own native objects: AppKit's
-- pull-down item array, UIKit's UIMenu tree and button configuration.
local M = {}

local function items(ns, menu)
	if ns.platform == "UIKit" then
		local result = {}
		for _, element in ipairs(menu.menu.children) do
			-- Inline sections are UIMenus; a separator is the gap between them.
			if element.children then
				if #result > 0 then table.insert(result, { separator = true }) end
				for _, action in ipairs(element.children) do
					table.insert(result, { title = action.title, checked = action.state == 1 })
				end
			else
				table.insert(result, { title = element.title, checked = element.state == 1 })
			end
		end
		return result
	end
	local result = {}
	-- Item 0 of a pull-down is its label, not a command.
	for index, item in ipairs(menu.itemArray) do
		if index > 1 then
			table.insert(result, item.separatorItem and { separator = true }
				or { title = item.title, checked = item.state == 1 })
		end
	end
	return result
end

local function title(ns, menu)
	if ns.platform == "UIKit" then return menu.configuration.title or "" end
	return menu.itemArray[1].title
end

function M.run(ns)
	local count = 0
	local function equal(actual, expected, message)
		assert(actual == expected, message .. ": expected " .. tostring(expected)
			.. ", got " .. tostring(actual))
		count = count + 1
	end
	local xml = require("ui.xml")
	local menu = xml.render([[
		<Menu systemImage="ellipsis" accessibilityLabel="Options">
			<MenuItem title="Starter" checked="true" />
			<MenuItem title="Habits" />
			<Separator />
			<MenuItem title="Starter" />
		</Menu>
	]], {}, ns)
	equal(title(ns, menu), "", "a symbol-only menu has no text label")
	local listed = items(ns, menu)
	equal(#listed, 4, "separator divides the menu without adding a command")
	equal(listed[1].title, "Starter", "first section keeps its order")
	equal(listed[1].checked, true, "checked item shows its checkmark")
	equal(listed[2].checked, false, "unchecked item has no checkmark")
	equal(listed[3].separator, true, "separator sits between the sections")
	equal(listed[4].title, "Starter", "a title may repeat in a later section")
	equal(listed[4].checked, false, "repeated title keeps its own state")
	local titled = xml.render([[<Menu title="Project" systemImage="app"><MenuItem title="A" /></Menu>]], {}, ns)
	equal(title(ns, titled), "Project", "a titled menu keeps its label")
	equal(title(ns, xml.render([[<Menu><MenuItem title="A" /></Menu>]], {}, ns)), "Menu",
		"a menu with neither title nor symbol keeps a readable label")

	if ns.platform == "UIKit" then
		-- UIButton.Configuration.Size: medium 0, small 1, mini 2, large 3.
		local small = xml.render([[<Button title="Undo" controlSize="small" style="bordered" />]], {}, ns)
		equal(small.configuration.buttonSize, 1, "small controlSize uses the small configuration")
		local plain = xml.render([[<Button title="Undo" style="bordered" />]], {}, ns)
		equal(plain.configuration.buttonSize, 0, "default controlSize stays medium")
		local ok = pcall(xml.render, [[<Button title="Undo" controlSize="huge" style="bordered" />]], {}, ns)
		equal(ok, false, "unknown controlSize is rejected")
	end
	return count
end

return M
