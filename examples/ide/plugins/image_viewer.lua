local ns = require("AppKit")
local bridge = require("bridge")
local App = require("App")

local ImageViewer = {}

local function clamp(value, minValue, maxValue)
	return math.min(maxValue, math.max(minValue, value))
end

local function createViewer(props)
	props = props or {}

	local path = props.path or props.file or ""
	if path == "" then
		error("ImageViewer requires props.path")
	end

	local title = props.title or App.basename(path)
	if title == "" then
		title = "Image Viewer"
	end

	local viewer = bridge._imageViewer(path, function(paths)
		local nextPath = paths and paths[1]
		if not nextPath or nextPath == "" then
			return
		end
		viewer.fitToWindow = true
		viewer.imagePath = nextPath
		if props.app and props.app.recent then
			props.app.recent:recordFile(nextPath)
		end
	end)

	viewer.flexGrow = 1
	viewer.fillWidth = true
	viewer.fillHeight = true

	local scale = 1.0
	local fitMode = false

	local function applyScale(nextScale)
		scale = clamp(nextScale, 0.05, 8.0)
		fitMode = false
		viewer.fitToWindow = false
		viewer.zoomScale = scale
	end

	local function fitToWindow()
		fitMode = true
		viewer.fitToWindow = true
	end

	local function actualSize()
		scale = 1.0
		fitMode = false
		viewer.fitToWindow = false
		viewer.zoomScale = scale
	end

	local function zoomBy(factor)
		applyScale(scale * factor)
	end

	viewer.imagePath = path

	local window = ns.Window {
		title = title,
		width = props.width or 920,
		height = props.height or 700,
		minWidth = props.minWidth or 480,
		minHeight = props.minHeight or 360,
		toolbarLabels = true,
		toolbar = {
			{
				id = "zoomOut",
				label = "Zoom Out",
				icon = "minus.magnifyingglass",
				action = function()
					zoomBy(0.85)
				end,
			},
			{
				id = "actualSize",
				label = "Actual Size",
				icon = "1.magnifyingglass",
				action = actualSize,
			},
			{
				id = "fitToWindow",
				label = "Fit",
				icon = "arrow.up.left.and.arrow.down.right",
				action = fitToWindow,
			},
			{
				id = "zoomIn",
				label = "Zoom In",
				icon = "plus.magnifyingglass",
				action = function()
					zoomBy(1.176)
				end,
			},
		},
		viewer,
	}

	return window
end

ImageViewer.id = "imageViewer"
ImageViewer.kind = "editor"
ImageViewer.title = "Image Viewer"
ImageViewer.summary = "A native image viewer for PNG, JPEG, GIF, TIFF, SVG, and other image files."
ImageViewer.capabilities = { "image", "preview" }
ImageViewer.activation = {
	onFileExtension = { "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "icns", "svg", "pdf" },
	onCommand = { "openImageViewer" },
}
ImageViewer.create = createViewer

local registered = App.getPlugin(ImageViewer.id)
if not registered then
	registered = App.registerPlugin(ImageViewer)
end

ImageViewer.spec = registered

return registered
