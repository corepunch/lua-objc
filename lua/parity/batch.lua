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

local function build(node, probes, ids)
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
	props.spacing, props.padding, props.size = node.spacing, node.padding, node.size
	props.fixedWidth, props.fixedHeight = node.width, node.height
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
			props[#props + 1] = build(child, probes, ids)
		end
	end
	local view = constructors[node.kind](props)
	if probe then probe.view = view end
	return view
end

function batch.measure(case, runId)
	assert(type(runId) == "string" and runId ~= "", "runId must be a nonempty string")
	assert(type(case.id) == "string" and case.id:match("^[%w_.-]+$")
		and case.id ~= "." and case.id ~= "..", "unsafe case id")
	dimension(case.width, "case.width")
	dimension(case.height, "case.height")
	local probes = {}
	local root = build(case.tree, probes, {})
	-- The unprobed native parent owns the proposal. Its ordinary ZStack layout
	-- measures and centers the tree; assigning bounds to the tree would mask
	-- intrinsic root text sizes and fixed-size root overflow.
	local viewport = ns.ZStack { root }
	return ns._parityMeasure(viewport, probes, {
		schema = 1, runId = runId, id = case.id, width = case.width, height = case.height,
	})
end

function batch.run(input, output)
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
			local json = batch.measure(case, input.runId)
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
	return batch.run(input, output)
end

return batch
