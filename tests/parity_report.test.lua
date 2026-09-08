local t = require("TestKit")

local prefix = "/tmp/lua_objc_parity_report_test"
local candidatePath = prefix .. ".xml"
local referencePath = prefix .. ".json"
local reportPath = prefix .. ".report.json"

local candidate = assert(io.open(candidatePath, "w"))
candidate:write([[<?xml version="1.0"?><Layout><View class="LuaTextField" identifier="text.node" x="10" y="20" width="30" height="40" contentClipped="false" outsideParent="false" /></Layout>]])
candidate:close()
local reference = assert(io.open(referencePath, "w"))
reference:write([[{"fixture":"test.case","generation":"test","actionCount":0,"probes":[{"id":"text.node","x":10,"y":20,"width":30,"height":40}]}]])
reference:close()

local command = "python3 scripts/parity/report_case.py --candidate-xml " .. candidatePath
	.. " --reference-json " .. referencePath .. " --out " .. reportPath .. " --strict"
local ok = os.execute(command)
t.expect(ok == true or ok == 0, "matching semantic frames pass strict report")

local wrong = assert(io.open(referencePath, "w"))
wrong:write([[{"fixture":"test.case","generation":"test","actionCount":0,"probes":[{"id":"missing","x":10,"y":20,"width":30,"height":40}]}]])
wrong:close()
local negative = os.execute(command)
t.expect(negative ~= true and negative ~= 0, "missing semantic node fails strict report")

os.remove(candidatePath)
os.remove(referencePath)
os.remove(reportPath)
os.remove(prefix .. ".report.html")
os.exit(t.summary() and 0 or 1)
