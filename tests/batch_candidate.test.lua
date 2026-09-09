_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local batch = require("parity.batch")
local function measure(tree, width, height, runId)
	return assert(ns._jsonParse(batch.measure({ id = "case", width = width or 300,
		height = height or 200, tree = tree }, runId or "regression")))
end
local tree = { id = "root", kind = "vstack", padding = 11, spacing = 7, children = {
	{ id = "first", kind = "text", text = "First", width = 90, height = 20 },
	{ id = "row", kind = "hstack", height = 40, padding = 3, spacing = 5, children = {
		{ id = "nested", kind = "text", text = "quote \" slash \\ newline\n日本語", width = 70, height = 15 },
		{ kind = "spacer" },
		{ id = "last", kind = "text", text = "Last", width = 50, height = 18 },
	} },
} }
local result = measure(tree)
t.assertEqual(result.schema, 1)
t.assertEqual(result.runId, "regression")
t.assertEqual(result.platform, "macos")
t.expect(type(result.os) == "string" and #result.os > 0)
t.expect(result.scale > 0)
t.assertEqual(#result.probes, 5, "all nonspacers including root")
local p = {}
for _, probe in ipairs(result.probes) do p[probe.id] = probe end
t.assertEqual(p.root.x, 0)
t.assertEqual(p.root.y, 55.5, "intrinsic stack is centered in the proposal")
t.assertEqual(p.root.width, 300)
t.assertEqual(p.root.height, 89)
t.assertEqual(p.first.x, 105, "native default horizontal centering")
t.assertEqual(p.first.y, 66.5, "top-left despite unflipped native root")
t.assertEqual(p.row.y, 93.5)
t.assertEqual(p.nested.x, 14, "nested x converted through native ancestors")
t.assertEqual(p.nested.y, p.row.y + (p.row.height - p.nested.height) / 2,
	"nested y converted through native ancestors with native centering")
t.assertEqual(p.nested.text, tree.children[2].children[1].text, "native text JSON round trip")
t.assertEqual(p.last.width, 50)

local empty = measure({ id = "empty", kind = "zstack" }, 0, 0)
t.assertEqual(#empty.probes, 1)
t.assertEqual(empty.probes[1].width, 0)
t.assertEqual(empty.probes[1].height, 0)
local spacer = measure({ kind = "spacer" })
t.assertEqual(#spacer.probes, 0)
t.expect(batch.measure({ id = "spacer", width = 1, height = 1, tree = {kind="spacer"} }, "r")
	:find('"probes":[]', 1, true) ~= nil, "empty probes serialize as array")
local overlay = measure({id="overlay", kind="zstack", children={
	{id="wide", kind="text", text="overflow", width=500, height=25},
	{id="tiny", kind="text", text="", width=10, height=10},
}})
t.assertEqual(#overlay.probes, 3)
t.assertEqual(overlay.probes[2].width, 500, "overflow is measured without clipping or compensation")
local larger = measure(tree, 600, 400, "next-run")
t.assertEqual(larger.runId, "next-run")
t.assertEqual(larger.probes[1].height, 89)
t.assertEqual(result.probes[1].height, 89, "subsequent cases do not mutate results")
t.assertEqual(measure(tree).probes[4].y, p.nested.y, "repeat deterministic after resize")
local small = measure({id="text", kind="text", text="Hello", size=10})
local sized = measure({id="s", kind="hstack", children={{id="t",kind="text",text="Hello",size=30}}})
t.expect(sized.probes[2].height > 10, "font size reaches native text measurement")
t.expect(small.probes[1].width < 300, "leaf root retains intrinsic width")
t.assertEqual(small.probes[1].x, (300 - small.probes[1].width) / 2, "intrinsic root centered in viewport")
t.assertEqual(small.probes[1].y, (200 - small.probes[1].height) / 2, "intrinsic root centered vertically")
local fixedRoot = measure({id="fixed", kind="text", text="fixed", width=500, height=25})
t.assertEqual(fixedRoot.probes[1].width, 500)
t.assertEqual(fixedRoot.probes[1].x, -100, "fixed root overflow is centered relative viewport")
t.assertEqual(fixedRoot.probes[1].y, 87.5)
local nativeText = ns.Text("before")
local nativeViewport = ns.ZStack { nativeText }
nativeText.text = "after mutation"
local nativeResult = assert(ns._jsonParse(ns._parityMeasure(nativeViewport,
	{{id="native",view=nativeText,text="incorrect input copy"}},
	{schema=1,runId="native",id="native",width=300,height=200})))
t.assertEqual(nativeResult.probes[1].text, "after mutation", "probe text is read from native control")

t.assertThrows(function() measure({ id="r", kind="bad" }) end)
t.assertThrows(function() measure({ kind="text" }) end)
t.assertThrows(function() measure({ id="r", kind="vstack", children={{id="r",kind="text"}} }) end)
t.assertThrows(function() measure(tree, -1) end)
t.assertThrows(function() batch.run({schema=1,cases={}}, "/tmp") end)

local output = os.tmpname()
os.remove(output)
local input = { schema=1, runId="file-run", cases={
	{id="hstack.w120.s0.p0.empty",width=300,height=200,tree=tree},
	{id="two",width=0,height=0,tree={id="root",kind="vstack"}},
} }
t.assertEqual(batch.run(input, output), 2)
t.assertEqual(ns._parityReadJSON(output .. "/done.json").count, 2)
t.assertEqual(ns._parityReadJSON(output .. "/done.json").runId, "file-run")
for _, case in ipairs(input.cases) do
	local file = assert(io.open(output .. "/" .. case.id .. ".json", "rb"))
	local saved = assert(ns._jsonParse(file:read("*a")))
	file:close()
	local nativeRead = ns._parityReadJSON(output .. "/" .. case.id .. ".json")
	t.assertEqual(nativeRead.runId, "file-run", "native file JSON reader")
	t.assertEqual(saved.id, case.id)
	t.assertEqual(saved.runId, "file-run")
	t.assertEqual(saved.width, case.width)
	os.remove(output .. "/" .. case.id .. ".json")
end
local inputPath = output .. "/input.json"
ns._parityWrite(inputPath, '{"schema":1,"runId":"model-run","cases":[{"id":"model","width":20,"height":30,"tree":{"id":"root","kind":"vstack"}}]}')
local model = require("examples.parity_batch.Model").new()
t.assertEqual(model:run(inputPath, output), 1, "streamed app model executes real native batch")
t.assertEqual(model.runId, "model-run")
t.assertEqual(ns._parityReadJSON(output .. "/model.json").probes[1].height, 0)
t.assertThrows(function() ns._parityReadJSON(output .. "/missing.json") end)
t.expect(type(ns._parityDocumentsDirectory()) == "string")
os.remove(inputPath)
os.remove(output .. "/model.json")
os.remove(output .. "/done.json")
t.assertThrows(function() batch.run({schema=1,runId="bad-run",cases={
	{id="bad",width=10,height=10,tree={kind="unknown"}},
}}, output) end)
t.assertEqual(ns._parityReadJSON(output .. "/error.json").runId, "bad-run")
local done = io.open(output .. "/done.json", "rb")
t.expect(done == nil, "failed batch never emits completion marker")
if done then done:close() end
os.remove(output .. "/error.json")
os.remove(output)
os.exit(t.summary() and 0 or 1)
