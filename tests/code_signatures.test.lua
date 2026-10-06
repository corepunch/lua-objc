local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")

-- Signatures are read off the main thread; Podcasts is signed by Apple and
-- names its Group Container among its app groups. An unsigned or missing
-- bundle is left out.
local signatures
ns.codeSignatures({"/System/Applications/Podcasts.app", "/nonexistent/Missing.app"}, function(result) signatures = result end)
t.assertEqual(signatures, nil, "signatures arrive asynchronously")
for _ = 1, 200 do if signatures then break end bridge._runLoopTick(0.02) end
t.expect(signatures ~= nil, "the completion runs on the main thread")
t.assertEqual(signatures["/nonexistent/Missing.app"], nil, "a missing bundle has no signature")
local podcasts = signatures["/System/Applications/Podcasts.app"]
if podcasts then
	local found = false
	for _, group in ipairs(podcasts.groups or {}) do if group:match("groups%.com%.apple%.podcasts$") then found = true end end
	t.expect(found, "Podcasts lists its app group")
end
ns.codeSignatures({}, function(result) signatures = result end)
for _ = 1, 50 do if next(signatures) == nil then break end bridge._runLoopTick(0.01) end
t.assertEqual(next(signatures), nil, "no paths give no signatures")
os.exit(t.summary() and 0 or 1)
