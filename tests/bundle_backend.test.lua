-- A device or release build refuses an app whose <Backend> uses our
-- development project (docs/backend.md): scripts/ipad/test_bundle_backend.py.
local t = require("TestKit")
local ok = os.execute("PYTHONDONTWRITEBYTECODE=1 python3 scripts/ipad/test_bundle_backend.py 2>/dev/null")
t.expect(ok == true or ok == 0, "builds that ship need the app's own Appwrite project")
os.exit(t.summary() and 0 or 1)
