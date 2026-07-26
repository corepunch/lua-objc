local ns = require("AppKit")
local bridge = require("bridge")
local PluginKit = require("PluginKit")
local TextEditor = require("Plugins.TextEditor")

local IDEKit = {}

IDEKit.Plugins = PluginKit
IDEKit.TextEditor = TextEditor

-- ControlBar: thin header strip, like Xcode's DVTControlBar.
-- Props: title (string), height (number, default 28), leading/buttons (view arrays).
function IDEKit.ControlBar(props)
	props = props or {}
	local height = props.height or 28

	-- Edge groups must retain their intrinsic width. HStack normally expands on
	-- its main axis, which would make a trailing button group occupy half the
	-- header and visually center its controls instead of pinning them right.
	local function edgeGroup(controls)
		return ns.HStack {
			spacing = 4,
			flexGrow = 0,
			flexShrink = 0,
			table.unpack(controls),
		}
	end

	-- Row of items: leading | title | Spacer | buttons
	local rowItems = {
		fixedHeight = height,
		paddingHorizontal = 8,
		alignment = "center",
		spacing = 6,
	}
	if props.leading then
		rowItems[#rowItems + 1] = edgeGroup(props.leading)
	end
	if props.title then
		rowItems[#rowItems + 1] = ns.Text {
			props.title,
			size = 11,
			weight = "semibold",
			color = "secondary",
		}
	end
	rowItems[#rowItems + 1] = ns.Spacer()
	local buttons = props.buttons or props.trailing
	if buttons then
		rowItems[#rowItems + 1] = edgeGroup(buttons)
	end

	-- fixedHeight pins the total bar height; flexGrow=0 prevents vertical expansion.
	-- fillWidth=true makes it span the full column width inside HSplit.
	return ns.VStack {
		fixedHeight = height + 1,   -- row + 1px separator
		flexGrow = 0,
		fillWidth = true,
		spacing = 0,
		ns.HStack(rowItems),
		ns.Separator(),
	}
end

-- _areaContent: wrap a content view so it fills remaining vertical space.
local function wrapContent(view)
	if not view then return nil end
	-- Give the content flexGrow=1 so it expands to fill the area under the ControlBar.
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- NavigatorArea: left sidebar panel.
-- Props: title, content (view), fixedWidth.
-- Mirrors Xcode's IDENavigatorArea / NSView_ControlledBy_IDENavigatorArea.
function IDEKit.NavigatorArea(props)
	props = props or {}
	return ns.VStack {
		fixedWidth = props.fixedWidth,
		spacing = 0,
		IDEKit.ControlBar { title = props.title },
		wrapContent(props.content),
	}
end

-- EditorArea: centre editing panel.
-- Props: title, content (view), leading/buttons ControlBar items.
-- Mirrors Xcode's IDEEditorArea / DVTSplitView_ControlledBy_IDEEditorArea.
function IDEKit.EditorArea(props)
	props = props or {}
	return ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		IDEKit.ControlBar {
			title = props.title,
			leading = props.leading,
			buttons = props.buttons or props.trailing,
		},
		wrapContent(props.content),
	}
end

-- PreviewArea: canvas / preview panel.
-- Props: title, content (view).
-- Mirrors Xcode's macOS preview: a real content view hosted inline (no chrome).
-- The canvas intercept (ns.Window → ns.VStack) is already equivalent to
-- Xcode's approach of displaying content-only with no NSWindow frame.
function IDEKit.PreviewArea(props)
	props = props or {}
	return ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		IDEKit.ControlBar {
			title = props.title or "Canvas",
			leading = props.leading,
			buttons = props.buttons or props.trailing,
		},
		wrapContent(props.content),
	}
end

-- WorkspaceLayout: root 3-panel HSplit.
-- Props: navigator, editor, preview — each a view produced by the area helpers.
-- Mirrors Xcode's workspace root NSSplitView.
function IDEKit.WorkspaceLayout(props)
	props = props or {}
	return ns.HSplit {
		flexGrow = 1,
		props.navigator,
		props.editor,
		props.preview,
	}
end

-- Editor: code-editor view backed by NSTextView.
-- The actual editor behavior lives in Plugins/TextEditor.lua; this wrapper
-- keeps the IDE canvas debounce and preserves the historical IDEKit.Editor API.
function IDEKit.Editor(props)
	props = props or {}
	local canvas = props.canvas
	local eval_version = 0

	local editor = TextEditor.create {
		initialCode = props.initialCode,
		language = props.language or "lua",
	}

	if canvas then
		editor:setChangeHandler(function(text)
			eval_version = eval_version + 1
			local version = eval_version
			bridge._timerAfter(0.3, function()
				if version ~= eval_version then return end
				IDEKit._evalIntoCanvas(canvas, text)
			end)
		end)
	end

	if canvas and props.initialCode then
		IDEKit._evalIntoCanvas(canvas, props.initialCode)
	end

	return editor
end

-- Canvas: the inline preview host view.
-- The canvas itself is a plain VStack that receives the result of _evalIntoCanvas.
-- This matches Xcode's macOS preview architecture: content-only, no window chrome.
function IDEKit.Canvas(props)
	return ns.VStack {
		flexGrow = 1,
	}
end

-- _evalIntoCanvas: evaluate Lua code and render the result into a canvas view.
-- ns.Window is intercepted so scripts that call ns.Window{} render inline.
function IDEKit._evalIntoCanvas(canvas, code)
	if not canvas then return end

	local result, err = bridge._eval(code, true)
	bridge._clearContainer(canvas)

	if err then
		local label = bridge._create("NSTextField")
		label.stringValue = err
		label.bezeled = false
		label.drawsBackground = false
		label.editable = false
		label.textColor = bridge._systemColor("secondary")
		bridge._perform(label, "sizeToFit")
		bridge._add(canvas, label)
	elseif result then
		bridge._add(canvas, result)
	end

	bridge._layout(canvas)
end

function IDEKit.renderCanvas(code, width, height)
	local result, err = bridge._eval(code, true)
	if err then return nil, err end
	local png = bridge._renderToPNG(result, width or 400, height or 300)
	return png, nil
end

return IDEKit
