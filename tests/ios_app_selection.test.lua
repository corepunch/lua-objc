local t = require("TestKit")

local function assertEntry(app, entry)
	local command = "make -n -o ios-host -o ios-packager ios ios-packager-run ios-internal-screenshot APP=" .. app
	local pipe = assert(io.popen(command))
	local output = pipe:read("*a")
	t.expect(pipe:close(), "Simulator command dry run succeeds")
	for _, recipe in ipairs({ "scripts/ios-run.sh", "--entry", "scripts/ios-internal-screenshot.sh" }) do
		t.expect(output:find(recipe .. ' "' .. entry .. '"', 1, true) ~= nil,
			recipe .. " selects " .. entry)
	end
end

assertEntry("adventure-arena", "apps/adventure-arena")
assertEntry("demo/hello", "demo/hello")
assertEntry("apps/adventure-arena/init.lua", "apps/adventure-arena/init.lua")
assertEntry("", "demo/hello")

local root = os.tmpname()
os.remove(root)
local function write(path, content)
	local file = assert(io.open(root .. "/" .. path, "w"))
	file:write(content)
	file:close()
end

assert(os.execute("mkdir -p " .. root .. "/bin " .. root .. "/scripts " .. root .. "/build/ios/LuaRuntime.app"))
write("bin/xcrun", [[#!/bin/sh
case "$2" in
	list) cat <<'JSON'
{"devices":{"iOS":[
	{"name":"iPhone 17 Pro","udid":"phone-id","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
	{"name":"iPad Air","udid":"tablet-id","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Air"}
]}}
JSON
	;;
	bootstatus|install|launch) printf '%s\n' "$*" >> "$IOS_TEST_LOG" ;;
	*) exit 1 ;;
esac
]])
write("bin/curl", [[#!/bin/sh
case "$2" in
	*/health) exit 0 ;;
	*/entry) printf '%s\n' '{"path":"apps/adventure-arena/init.lua"}' ;;
	*) exit 1 ;;
esac
]])
write("bin/open", "#!/bin/sh\necho open >> \"$IOS_TEST_LOG\"\nexit 1\n")
write("bin/python3", "#!/bin/sh\nunset DEVELOPER_DIR\nexec /usr/bin/python3 \"$@\"\n")
write("build/lua-objc-packager", "#!/bin/sh\nexit 1\n")
assert(os.execute("cp scripts/ios-run.sh " .. root .. "/scripts/ && chmod +x " .. root .. "/bin/* " .. root .. "/build/lua-objc-packager"))

local environment = "PATH=" .. root .. "/bin:$PATH DEVELOPER_DIR=" .. root .. "/xcode IOS_TEST_LOG=" .. root .. "/simctl.log "
local function resolveDevice(argument, expected)
	local pipe = assert(io.popen(environment .. "python3 scripts/ios-simulator-device.py " .. argument))
	t.assertEqual(pipe:read("*l"), expected, "Resolved simulator " .. argument)
	t.expect(pipe:close(), "Simulator selection succeeds")
end
resolveDevice("''", "phone-id")
resolveDevice("'iPad Air'", "tablet-id")
resolveDevice("'phone-id'", "phone-id")

local command = environment .. "DEVICE=phone-id LUA_OBJC_RUN_NONBLOCKING=1 /bin/sh " .. root .. "/scripts/ios-run.sh apps/adventure-arena"
t.expect(os.execute(command .. " >/dev/null"), "Simulator launch succeeds with no Simulator.app")
local log = assert(io.open(root .. "/simctl.log"))
t.assertEqual(log:read("*a"), table.concat({
	"simctl bootstatus phone-id -b",
	"simctl install phone-id " .. root .. "/build/ios/LuaRuntime.app",
	"simctl launch --terminate-running-process phone-id org.luaobjc.host",
	"",
}, "\n"), "Boot, install, and launch the selected simulator by UDID")
log:close()
os.execute("rm -rf " .. root)

os.exit(t.summary() and 0 or 1)
