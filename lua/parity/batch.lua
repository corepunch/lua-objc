-- One Lua state constructs and measures all cases. UIKit callers may supply
-- decoded streamed input directly; no files need to be bundled in the host.
local ns = require("ns")
local batch = {}
local constructors = {
	text = ns.Text, hstack = ns.HStack, vstack = ns.VStack,
	zstack = ns.ZStack, spacer = ns.Spacer,
}

local function dimension(value, name)
	assert(type(value) == "number" and value >= 0 and value < math.huge,
		name .. " must be a finite nonnegative number")
end

local function build(node, probes, ids, swiftui)
	assert(type(node) == "table" and constructors[node.kind], "invalid node kind")
	if node.kind ~= "spacer" then
		assert(type(node.id) == "string" and node.id ~= "", "node needs an id")
		assert(not ids[node.id], "duplicate node id: " .. node.id)
		ids[node.id] = true
	end
	local props = {}
	for _, key in ipairs({ "spacing", "padding", "size", "width", "height" }) do
		if node[key] ~= nil then dimension(node[key], key) end
	end
	props.spacing, props.size = node.spacing, node.size
	if not swiftui then props.padding = node.padding end
	props.fixedWidth, props.fixedHeight = node.width, node.height
	-- The normal AppKit stack constructors are flexible because application
	-- roots usually consume their window. SwiftUI stacks in this fixture are
	-- measured intrinsically by the surrounding fixed frame, however, so the
	-- parity adapter must remove that application-level default. Spacers keep
	-- their native flexibility and still expand when a stack proposes space.
	if swiftui and (node.kind == "hstack" or node.kind == "vstack" or node.kind == "zstack") then
		props.flexGrow = 0
		props.flexShrink = 0
		props.fillWidth = false
		props.fillHeight = false
	end
	local probe
	if node.kind ~= "spacer" then
		probe = { id = node.id }
		probes[#probes + 1] = probe
	end
	if node.kind == "text" then
		assert(node.text == nil or type(node.text) == "string", "text must be a string")
		props[1] = node.text or ""
	else
		for _, child in ipairs(node.children or {}) do
			props[#props + 1] = build(child, probes, ids, swiftui)
		end
	end
	local view = constructors[node.kind](props)
	if swiftui and node.kind == "text" and node.width == nil then
		-- NSTextField's intrinsic bounds include its two-point cell inset on
		-- each horizontal edge; SwiftUI Text measures only its glyph content.
		-- Keep this normalization local to the reference adapter rather than
		-- changing the sizing contract of production text controls.
		local frame = view.frameSize
		if frame and frame.width > 4 then
			view.fixedWidth = frame.width - 4
		end
	end
	-- Padding is an outer SwiftUI modifier. Represent it with a native
	-- intrinsic ZStack wrapper so a fixed frame on the node remains inside the
	-- padding, instead of being overwritten by the production layout property.
	if swiftui and node.padding ~= nil then
		view = constructors.zstack {
			padding = node.padding,
			flexGrow = 0,
			flexShrink = 0,
			fillWidth = false,
			fillHeight = false,
			view,
		}
	end
	if node.kind ~= "spacer" then
		probe.view = view
	end
	return view
end

function batch.measure(case, runId, swiftui)
	assert(type(runId) == "string" and runId ~= "", "runId must be a nonempty string")
	assert(type(case.id) == "string" and case.id:match("^[%w_.-]+$")
		and case.id ~= "." and case.id ~= "..", "unsafe case id")
	dimension(case.width, "case.width")
	dimension(case.height, "case.height")
	local probes = {}
	local root = build(case.tree, probes, {}, swiftui == true)
	-- The unprobed native parent owns the proposal. Its ordinary ZStack layout
	-- measures and centers the tree; assigning bounds to the tree would mask
	-- intrinsic root text sizes and fixed-size root overflow.
	local viewport = ns.ZStack { root }
	return ns._parityMeasure(viewport, probes, {
		schema = 1, runId = runId, id = case.id, width = case.width, height = case.height,
	})
end

function batch.run(input, output, swiftui)
	assert(type(input) == "table" and input.schema == 1, "expected batch schema 1")
	assert(type(input.runId) == "string" and input.runId ~= "", "missing runId")
	assert(type(input.cases) == "table", "missing cases")
	assert(type(output) == "string" and output ~= "", "missing output directory")
	local ids = {}
	for _, case in ipairs(input.cases) do
		assert(not ids[case.id], "duplicate case id")
		ids[case.id] = true
	end
	local ok, err = pcall(function()
		for _, case in ipairs(input.cases) do
			local json = batch.measure(case, input.runId, swiftui == true)
			ns._parityWrite(output .. "/" .. case.id .. ".json", json)
			collectgarbage("collect")
		end
	end)
	if not ok then
		ns._parityWrite(output .. "/error.json", ns._parityJSON { runId = input.runId, error = tostring(err) })
		error(err, 0)
	end
	ns._parityWrite(output .. "/done.json", ns._parityJSON { runId = input.runId, count = #input.cases })
	return #input.cases
end

function batch.runEnvironment()
	local path = assert(os.getenv("PARITY_BATCH_INPUT"), "PARITY_BATCH_INPUT is required")
	local output = assert(os.getenv("PARITY_BATCH_OUTPUT"), "PARITY_BATCH_OUTPUT is required")
	local source
	if ns._readFile and path:sub(1, 1) ~= "/" then
		-- The UIKit host resolves repository-relative paths via its packager.
		source = assert(ns._readFile(path))
	else
		local file = assert(io.open(path, "rb"))
		source = file:read("*a")
		file:close()
	end
	local input, err = ns._jsonParse(source)
	assert(input, err)
	return batch.run(input, output, true)
end

return batch
