local Model = require("data.model")
local Items = require("apps.diskmap.models.Items")
local Knowledge = require("apps.diskmap.knowledge.Categories")

-- The sidebar's pages (knowledge/Categories.lua) with their measured totals.
-- A computed model, as a database view is: the rows are the knowledge list,
-- the numbers come from Items.
local Categories, Category = Model:extend("categories", {source = function() return Knowledge end})

function Category:items() return Items:inCategory(self.id) end
function Category:totals() return Items:totals(self.id) end
function Category:bytes() return (Items:totals(self.id)) end
function Category:safeBytes() local _, safe = Items:totals(self.id); return safe end

-- Overview rows, largest first; a category with nothing measured is listed
-- last, so an empty one never leads the page.
function Categories:ranked()
	local rows = self:all()
	table.sort(rows, function(a, b)
		local x, y = a:bytes(), b:bytes()
		if x ~= y then return x > y end
		return a.id < b.id
	end)
	return rows
end

return Categories
