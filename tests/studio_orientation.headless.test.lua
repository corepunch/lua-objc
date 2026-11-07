local t = require("TestKit")
local ok = os.execute("PYTHONDONTWRITEBYTECODE=1 python3 scripts/ipad/test_bundle_orientation.py")
t.expect(ok,"device and simulator bundles exclude portrait orientations")
os.exit(t.summary() and 0 or 1)
