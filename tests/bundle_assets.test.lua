-- A standalone app bundle carries the shared asset kits (assets/kenney/<kit>)
-- its sources name: scripts/ipad/test_bundle_assets.py.
local t = require("TestKit")
local ok = os.execute("PYTHONDONTWRITEBYTECODE=1 python3 scripts/ipad/test_bundle_assets.py 2>/dev/null")
t.expect(ok == true or ok == 0, "bundles copy the asset kits their app names")
os.exit(t.summary() and 0 or 1)
