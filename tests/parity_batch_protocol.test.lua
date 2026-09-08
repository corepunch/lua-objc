local t = require("TestKit")
local ok = os.execute("python3 tests/parity/batch/test_protocol.py")
t.expect(ok == true or ok == 0, "batch evidence protocol rejects false passes")
os.exit(t.summary() and 0 or 1)
