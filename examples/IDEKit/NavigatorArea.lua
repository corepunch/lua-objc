local ns = require("AppKit")

local function NavigatorArea(props)
	props = props or {}
	local onRowSelect = props.onRowSelect

	local fileTree = ns.OutlineView {
		header = false,
		bordered = false,
		style = "sourceList",
		flexGrow = 1,
		columns = {
			{ id = "name", title = "Name", systemImage = "doc.text" },
		},
		data = props.files or {},
	}

	if onRowSelect then
		fileTree:onRowSelect(function(list, rowIndex, rowData, modifiers)
			if rowData and rowData.path and not rowData.directory then
				onRowSelect(rowData.path, modifiers and modifiers.command)
			end
		end)
	end

	local view = ns.VStack {
		spacing = 0,
		fileTree,
	}

	return view, fileTree
end

return NavigatorArea
