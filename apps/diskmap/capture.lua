-- DISKMAP_CAPTURE_DIR chooses the output folder. Use --showcase for the
-- same deterministic disk, --isolated for a sidebar-free page workspace.
local ns = require("AppKit")
return function(capture, app)
	local directory = os.getenv("DISKMAP_CAPTURE_DIR") or "/tmp/diskmap-pages"
	local function shot(id, width, height, appearance, suffix)
		app.window.size = ns.Size(width, height)
		capture.appearance(appearance)
		app:show(id, id == "folder" and {path = app.env.model.home .. "/Developer"} or {})
		capture.shot(directory .. "/" .. id .. "-" .. width .. "-" .. appearance .. (suffix or ""))
	end
	for _, section in ipairs(app.env.manifest.sections) do
		for _, entry in ipairs(section.pages) do
			for _, width in ipairs({1100, app.launch.isolated and 724 or 950}) do
				for _, appearance in ipairs({"light", "dark"}) do shot(entry.id, width, width == 1100 and 760 or 580, appearance) end
			end
		end
	end
	-- Resizing and state variants use the same retained requests and actions.
	shot("map", 1400, 900, "light", "-large")
	app:show("map", {style = "rectangles"}); capture.shot(directory .. "/map-rectangles")
	app:search("files", "no-matching-file"); capture.shot(directory .. "/files-empty")
	app:search("files", ""); app.page.refs.files:selectRow(0); capture.shot(directory .. "/files-selected")
end
