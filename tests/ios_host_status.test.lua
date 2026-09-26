_G.__headless = true

-- The iOS host's status screen is the system empty state, not a custom
-- error panel, and every failure offers a way back.

local t = require("TestKit")

local function source(path)
	local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text
end

local view = source("ios/LuaRuntime/LRTErrorViewController.m")
t.expect(view:find("UIContentUnavailableConfiguration emptyConfiguration", 1, true) ~= nil,
	"errors use the system empty-state configuration")
t.expect(view:find("UIContentUnavailableConfiguration loadingConfiguration", 1, true) ~= nil,
	"waiting for the packager shows the system loading state")
t.expect(view:find("Try Again", 1, true) and view:find("Copy Details", 1, true),
	"an error offers retry and the raw details")
t.expect(not view:find("colorWithRed", 1, true) and not view:find("UITextView", 1, true)
	and not view:find("monospacedSystemFont", 1, true),
	"no hand-made colors or text walls imitate an error screen")

local controller = source("ios/LuaRuntime/LRTApplicationController.m")
t.expect(controller:find("- (void)showError:(NSError *)error", 1, true) ~= nil,
	"failures carry an NSError so the screen can explain them")
t.expect(controller:find("File Not Found", 1, true) ~= nil, "a missing entry is explained in plain language")
t.expect(controller:find("- (void)restart", 1, true) and controller:find("[weakSelf restart]", 1, true),
	"Try Again rebuilds the app from the packager's current entry")
t.expect(not controller:find("showError:[^%]\n]*localizedDescription")
	and not controller:find("showError:%[NSString"),
	"no call site flattens an error into a raw string")

local loader = source("ios/LuaRuntime/LRTResourceLoader.m")
t.expect(loader:find("LRTResourceLoaderPathKey: request_path", 1, true) ~= nil,
	"HTTP errors report the project path that was requested")

os.exit(t.summary() and 0 or 1)
