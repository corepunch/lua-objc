local ns = require("AppKit")
local Sheet = {}
local INSET = 80
function Sheet.present(sheet, parent)
	local width = parent.size.width - INSET
	if width > 0 and sheet.size.width > width then
		sheet:resize(width, sheet.size.height)
		sheet:layout()
	end
	return ns.presentSheet(sheet, parent)
end
return Sheet
