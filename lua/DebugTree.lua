-- View tree dumping utility for layout debugging.
-- Writes the frame of every view in a window/content-view hierarchy as XML.
-- Usage: DebugTree.write(view, "layout.xml")

local DebugTree = {}

local function safe_subviews(v)
	local ok, subs = pcall(function() return v.subviews end)
	if not ok then return {} end
	return subs or {}
end

local function pushIndent(indent)
	return indent .. "  "
end

local function dumpView(v, label, indent, out, absX, absY, parentW, parentH)
	local f = v.frame
	local px = absX + f.origin.x
	local py = absY + f.origin.y
	local pw = f.size.width
	local ph = f.size.height

	local attrs = string.format(
		'label="%s" x="%.0f" y="%.0f" w="%.0f" h="%.0f" parentW="%.0f" parentH="%.0f" absX="%.0f" absY="%.0f"',
		label, f.origin.x, f.origin.y, pw, ph, parentW, parentH, px, py)

	local subs = safe_subviews(v)
	local subVals = {}
	for k, sub in pairs(subs) do
		subVals[#subVals + 1] = {idx = k, view = sub}
	end
	table.sort(subVals, function(a, b) return a.idx < b.idx end)

	if #subVals == 0 then
		out[#out + 1] = indent .. "<View " .. attrs .. "/>"
		return
	end

	out[#out + 1] = indent .. "<View " .. attrs .. ">"
	for _, entry in ipairs(subVals) do
		dumpView(entry.view, "sub" .. entry.idx, pushIndent(indent), out,
			px, py, pw, ph)
	end
	out[#out + 1] = indent .. "</View>"
end

function DebugTree.write(view, path)
	local out = {}
	out[#out + 1] = '<?xml version="1.0"?>'
	out[#out + 1] = '<ViewHierarchy>'
	dumpView(view, "root", "  ", out, 0, 0, 0, 0)
	out[#out + 1] = '</ViewHierarchy>'

	local f = io.open(path or "/tmp/view_tree.xml", "w")
	f:write(table.concat(out, "\n") .. "\n")
	f:close()
	return true
end

return DebugTree
