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

return Quotes
