local t = require("TestKit")
local ok = os.execute("PYTHONDONTWRITEBYTECODE=1 python3 scripts/ipad/test_studio_github_verify.py")
t.expect(ok, "publishing uses the explicit environment token without a Keychain fallback")
os.exit(t.summary() and 0 or 1)
