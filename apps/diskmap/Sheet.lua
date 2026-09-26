local ns = require("AppKit")
local Sheet = {}
-- Review sheets keep an 80 point margin inside the window on narrow windows.
local INSET = 80
-- Presents a sheet built by `build`, which returns (sheet, refs), like
-- ns.presentSheet; the sheet owns everything the builder creates.
function Sheet.present(build, parent)
	return ns.presentSheet(function()
		local sheet, refs = build()
		local width = parent.size.width - INSET
		if width > 0 and sheet.size.width > width then sheet:resize(width, sheet.size.height) end
		return sheet, refs
	end, {parent = parent})
end
return Sheet
