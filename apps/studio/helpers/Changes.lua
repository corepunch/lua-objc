-- Line counts for a change card: how many lines a file gained and lost
-- between two texts. A line present in the new text and not the old counts
-- as added, the reverse as removed; a line that only moved counts for
-- neither, so a reordered file reads as a small change, as it is. Pure.
local Changes = {}

local function tally(text)
	local counts = {}
	for line in (text or ""):gmatch("([^\n]*)\n?") do
		if line ~= "" then counts[line] = (counts[line] or 0) + 1 end
	end
	return counts
end

--- Added and removed line counts from `old` to `new`.
function Changes.count(old, new)
	local before, added, removed = tally(old), 0, 0
	for line in (new or ""):gmatch("([^\n]*)\n?") do
		if line ~= "" then
			if before[line] and before[line] > 0 then before[line] = before[line] - 1 else added = added + 1 end
		end
	end
	for _, count in pairs(before) do removed = removed + count end
	return added, removed
end

--- One entry per changed path, {path, added, removed}, with `path`
--- relative to `prefix`, in the order given.
function Changes.summary(before, after, paths, prefix)
	local result = {}
	for _, path in ipairs(paths) do
		local added, removed = Changes.count(before[path], after[path])
		local relative = prefix and path:sub(1, #prefix) == prefix and path:sub(#prefix + 1) or path
		table.insert(result, { path = relative, added = added, removed = removed })
	end
	return result
end

return Changes
