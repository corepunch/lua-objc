-- scripts/assets/import_kenney.py: models are checked against their OBJ
-- twins; Unity-era exports are turned, moved and recoloured to match;
-- mismatches are refused (scripts/assets/test_import_kenney.py).
local t = require("TestKit")
local ok = os.execute("PYTHONDONTWRITEBYTECODE=1 python3 -I scripts/assets/test_import_kenney.py >/dev/null 2>&1")
t.expect(ok == true or ok == 0, "kit import corrects Unity-era exports and refuses mismatches")
os.exit(t.summary() and 0 or 1)
