--[[
  ui/chartkeys.lua — keyboard navigation and type-to-filter for charts.

  SectorChart and Treemap share it. Marks are `{id, parent, label, value}`;
  the chart supplies them and applies the resulting focus and filter.

    left / right      previous or next sibling, around the parent
    up / down         the parent, or the largest child
    tab / backtab     the largest sibling, then the next largest
    return            activates the focused mark (drills into a group)
    delete            removes a typed character, or goes up a level
    escape            clears the filter, then the focus
    characters        filter marks by label; matches stay, others dim

  `Keys.new(marks, handlers)` returns an object with `handle(key)` for the
  pointer view's onKey, `focus`, `filter` and `matches(mark)`. Handlers:
  `focus(id)` after the focus moves, `activate(id)`, `back()` and
  `filtered()` after the filter changes.
]]

local Keys = {}
Keys.__index = Keys

function Keys.new(marks, handlers)
	return setmetatable({marks = marks, handlers = handlers or {}, filter = ""}, Keys)
end

local function siblings(marks, parent)
	local list = {}
	for _, mark in ipairs(marks) do
		if (mark.parent or "") == (parent or "") then table.insert(list, mark) end
	end
	return list
end

local function largestFirst(list)
	local sorted = {}
	for _, mark in ipairs(list) do table.insert(sorted, mark) end
	table.sort(sorted, function(a, b)
		if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	return sorted
end

function Keys:find(id)
	for _, mark in ipairs(self.marks) do if mark.id == id then return mark end end
end

-- Whether a mark matches the typed filter: its label contains it.
function Keys:matches(mark)
	if self.filter == "" then return true end
	return tostring(mark.label or ""):lower():find(self.filter:lower(), 1, true) ~= nil
end

function Keys:setFocus(mark)
	if not mark then return false end
	self.focus = mark.id
	if self.handlers.focus then self.handlers.focus(mark.id) end
	return true
end

function Keys:setFilter(text)
	self.filter = text
	if self.handlers.filtered then self.handlers.filtered() end
	-- Focus follows the largest match, as Disktree's filter does.
	if text ~= "" then
		for _, mark in ipairs(largestFirst(self.marks)) do
			if self:matches(mark) then return self:setFocus(mark) end
		end
	end
	return true
end

function Keys:handle(key)
	local current = self.focus and self:find(self.focus)
	if not current then
		if key == "left" or key == "right" or key == "up" or key == "down" or key == "tab" or key == "backtab" then
			return self:setFocus(largestFirst(siblings(self.marks, nil))[1])
		end
	end
	if key == "left" or key == "right" then
		local list = siblings(self.marks, current.parent)
		for index, mark in ipairs(list) do
			if mark == current then
				local step = key == "right" and 1 or -1
				return self:setFocus(list[(index - 1 + step) % #list + 1])
			end
		end
	elseif key == "up" then
		return self:setFocus(current.parent and current.parent ~= "" and self:find(current.parent) or nil)
	elseif key == "down" then
		return self:setFocus(largestFirst(siblings(self.marks, current.id))[1])
	elseif key == "tab" or key == "backtab" then
		local ranked = largestFirst(siblings(self.marks, current.parent))
		for index, mark in ipairs(ranked) do
			if mark == current then
				local step = key == "tab" and 1 or -1
				return self:setFocus(ranked[(index - 1 + step) % #ranked + 1])
			end
		end
	elseif key == "return" then
		if current and self.handlers.activate then self.handlers.activate(current.id) end
		return current ~= nil
	elseif key == "delete" then
		if self.filter ~= "" then return self:setFilter(self.filter:sub(1, -2)) end
		if self.handlers.back then self.handlers.back() end
		return true
	elseif key == "escape" then
		if self.filter ~= "" then return self:setFilter("") end
		self.focus = nil
		if self.handlers.focus then self.handlers.focus(nil) end
		return true
	elseif #key >= 1 and key:match("^[%w%s%p]+$") then
		return self:setFilter(self.filter .. key)
	end
	return false
end

return Keys
