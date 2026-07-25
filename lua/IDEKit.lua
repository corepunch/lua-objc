local ns = require("AppKit")
local bridge = require("bridge")

local IDEKit = {}

function IDEKit.FileTree(props)
	props = props or {}
	local list = ns.List {
		width = props.width or 220,
		height = props.height or 400,
		header = false,
		bordered = true,
		flexGrow = 1,
		columns = {
			{ id = "name", title = "Name" },
		},
		data = props.files or {},
	}

	if props.onSelect then
		bridge._callback(list, function()
			print("selection changed")
		end)
	end

	return list
end

function IDEKit.Editor(props)
	props = props or {}
	local canvas = props.canvas
	local editor = bridge._textView()

	if props.initialCode then
		bridge._textViewSetText(editor, props.initialCode)
	end

	local eval_version = 0

	bridge._textViewOnChange(editor, function(text)
		eval_version = eval_version + 1
		local version = eval_version
		bridge._timerAfter(0.3, function()
			if version ~= eval_version then return end
			IDEKit._evalIntoCanvas(canvas, text)
		end)
	end)

	if props.initialCode and canvas then
		IDEKit._evalIntoCanvas(canvas, props.initialCode)
	end

	return editor
end

function IDEKit._evalIntoCanvas(canvas, code)
	if not canvas then return end

	local result, err = bridge._eval(code)
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

function IDEKit.Canvas(props)
	return ns.VStack {
		flexGrow = 1,
	}
end

function IDEKit.IdeApp()
	local canvas = IDEKit.Canvas { flexGrow = 1 }
	local editor = IDEKit.Editor {
		flexGrow = 1,
		canvas = canvas,
		initialCode = [=[
-- Try changing the text and see it update in the canvas
ns.VStack {
	padding = 16,
	alignment = "leading",
	ns.Title "Hello, lua-objc",
	ns.Text {
		"Edit the code on the left. The canvas updates as you type.",
		size = 13,
		color = "secondary",
	},
	ns.Spacer(),
	ns.Button {
		title = "A Button",
		action = function() print("clicked") end,
	},
}
]=],
	}

	local fileTree = IDEKit.FileTree {
		files = {
			{ name = "hello.lua" },
			{ name = "list.lua" },
			{ name = "live.lua" },
			{ name = "weather.lua" },
			{ name = "mail.lua" },
			{ name = "welcome.lua" },
		},
	}

	local topBar = ns.HStack {
		fixedHeight = 38,
		paddingHorizontal = 12,
		alignment = "center",
		ns.Text {
			"lua-objc IDE",
			size = 13,
			weight = "semibold",
		},
		ns.Spacer(),
	}

	local leftPanel = ns.VStack {
		fixedWidth = 220,
		spacing = 0,
		ns.HStack {
			fixedHeight = 28,
			paddingHorizontal = 10,
			alignment = "center",
			ns.Text {
				"Files",
				size = 11,
				weight = "semibold",
				color = "secondary",
			},
		},
		fileTree,
	}

	local centerColumn = ns.VStack {
		flexGrow = 1,
		spacing = 0,
		ns.HStack {
			fixedHeight = 28,
			paddingHorizontal = 10,
			alignment = "center",
			ns.Text {
				"Editor",
				size = 11,
				weight = "semibold",
				color = "secondary",
			},
		},
		editor,
	}

	local rightPanel = ns.VStack {
		flexGrow = 1,
		spacing = 0,
		ns.HStack {
			fixedHeight = 28,
			paddingHorizontal = 10,
			alignment = "center",
			ns.Text {
				"Canvas",
				size = 11,
				weight = "semibold",
				color = "secondary",
			},
		},
		canvas,
	}

	return ns.Window {
		title = "lua-objc IDE",
		width = 1100,
		height = 680,
		minWidth = 800,
		minHeight = 500,

		ns.VStack {
			flexGrow = 1,
			spacing = 0,
			topBar,
			ns.Divider(),
			ns.HSplit {
				flexGrow = 1,
				leftPanel,
				ns.Divider { orientation = "vertical" },
				centerColumn,
				ns.Divider { orientation = "vertical" },
				rightPanel,
			},
		},
	}
end

return IDEKit
