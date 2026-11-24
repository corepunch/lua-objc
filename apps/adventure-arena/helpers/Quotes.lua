local Quotes = {}

-- Ranges count Unicode scalars, like Paragraph's inline formatting records.
function Quotes.ranges(text)
	local ranges, start, opening = {}, nil, nil
	local position = 0
	for _, code in utf8.codes(text or "") do
		local char = utf8.char(code)
		if not start and (char == '"' or char == '“') then
			start, opening = position, char
		elseif start and ((opening == '"' and char == '"') or (opening == '“' and char == '”')) then
			table.insert(ranges, { location = start, length = position - start + 1 })
			start, opening = nil, nil
		end
		position = position + 1
	end
	return ranges
end

-- Use the outer marks to delimit quotes. The displayed blocks keep their
-- inner punctuation, with bold ranges rebased to the visible characters.
function Quotes.blocks(text, links)
	local blocks, cursor = {}, 1
	local function append(first, last, quoted, punctuation)
		local piece = text:sub(first, last)
		local start = piece:match("^%s*()")
		local content = piece:sub(start):gsub("%s+$", "")
		if content == "" and not punctuation then return end
		local offset = utf8.len(text:sub(1, first + start - 2))
		local length = utf8.len(content)
		local ranges = {}
		for _, link in ipairs(links or {}) do
			local left = math.max(offset, link.location)
			local right = math.min(offset + length, link.location + link.length)
			if left < right then table.insert(ranges, { location = left - offset, length = right - left }) end
		end
		table.insert(blocks, { text = content .. (punctuation or ""), quoted = quoted, ranges = ranges })
	end
	for _, range in ipairs(Quotes.ranges(text)) do
		local first = utf8.offset(text, range.location + 1)
		local inside = utf8.offset(text, range.location + 2)
		local closing = utf8.offset(text, range.location + range.length)
		local after = utf8.offset(text, range.location + range.length + 1)
		local punctuation = text:match("^[.,;:!?]+", after)
		append(cursor, first - 1, false)
		append(inside, closing - 1, true, punctuation)
		cursor = after + #(punctuation or "")
	end
	append(cursor, #text, false)
	return blocks
end

function Quotes.blockKey(paragraph, part)
	return tostring(paragraph) .. (part == 1 and "" or "_" .. part)
end

return Quotes
