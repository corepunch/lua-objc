local t = require("TestKit")
local paths = require("packager.paths")

t.assertEqual(paths.kind("examples/hello/Model.lua"), "model", "Model.lua is model")
t.assertEqual(paths.kind("examples/hello/init.lua"), "init", "init.lua is init")
t.assertEqual(paths.kind("examples/hello/Controller.lua"), "controller", "Controller.lua")
t.assertEqual(paths.kind("examples/hello/views/Window.etlua"), "view", "etlua is view")
t.assertEqual(paths.kind("lua/ui/xml.lua"), "runtime", "xml.lua is runtime")
t.assertEqual(paths.kind("examples/weather/assets/sunny.svg"), "asset", "svg is asset")
t.assertEqual(paths.kind("src/uikit/views.m"), "other", ".m is other")

t.expect(paths.watched("examples/hello/Controller.lua"), "watch app lua")
t.expect(not paths.watched("src/uikit/views.m"), "do not watch native sources")
t.expect(not paths.watched("third_party/lua-5.4.8/src/lapi.c"), "do not watch vendored lua")

local rel, err = paths.moduleRel("UIKitNative")
t.expect(rel == nil, "UIKitNative is not served")
t.assertEqual(err, "native", "native module error")
t.assertEqual(paths.moduleRel("UIKit"), "lua/embedded/UIKit.lua", "UIKit is streamed")
t.assertEqual(paths.moduleRel("ui.xml"), "lua/ui/xml.lua", "ui.xml mapping")
t.assertEqual(paths.moduleRel("examples.hello.Controller"),
	"examples/hello/Controller.lua", "app module mapping")

local full, norm = paths.jail("/tmp/repo", "examples/hello/views/Window.etlua")
t.assertEqual(norm, "examples/hello/views/Window.etlua", "jail keeps relative path")
t.expect(full:find("examples/hello/views/Window.etlua", 1, true), "jail joins root")

local escaped = paths.normalize("examples/hello/views/../../../views/AppWindow.etlua")
t.assertEqual(escaped, "views/AppWindow.etlua", "normalize resolves template extends")

local bad = paths.normalize("../../etc/passwd")
t.expect(bad == nil, "normalize rejects escaping ..")

t.expect(paths.normalize("/etc/passwd") == nil, "normalize rejects absolute paths")

os.exit(t.summary() and 0 or 1)
