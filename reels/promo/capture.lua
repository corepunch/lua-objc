-- Captures every app state the promo shows, with the apps themselves:
--
--   ./lua-objc reels/promo/capture.lua [mac] [iphone] [studio]
--
-- (all three when none is named; `make promo-reel-captures` runs it). Each
-- version of each app (Edits.lua) gets its own root under
-- build/reel-promo/roots: symbolic links to this checkout, with a copy of
-- the app that has the later edits reverse-applied. From those roots:
--
--   mac     lua-objc --capture: the window's content and its layout dump,
--           so the reel can cut pieces by view identifier
--   iphone  the UIKit host on the iPhone Simulator, streamed from the root
--           by the packager, captured with simctl
--   studio  Ledger bundled for the iPad Simulator, and Lua Studio there,
--           bundled with each version of Todo and the conversation that
--           produced it (LUA_STUDIO_SHOWCASE)
--
-- Captures land in reels/promo/captures/, which is generated, not
-- committed. Simulator steps need Xcode and a booted-able simulator; the
-- simulator screen is captured headlessly and Simulator.app never opens.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local Edits = require("Edits")
local Conversation = require("Conversation")

local repo = io.popen("pwd"):read("l")
local OUT = repo .. "/" .. here .. "captures"
local ROOTS = repo .. "/build/reel-promo/roots"
local OVERLAYS = repo .. "/build/reel-promo/overlays"
local SIZE = { width = 1200, height = 760 }
local DEVICES = { iphone = "iPhone 17 Pro", ipad = "iPad Pro 13-inch (M5)" }
-- A launched app streams its Lua and settles; the screen is captured after.
local SETTLE = { host = 7, studio = 8 }
local PACKAGER = "http://127.0.0.1:8081"

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function sh(command)
	local ok = os.execute(command)
	if not ok then error("capture: command failed: " .. command, 0) end
end

local function read(command)
	local pipe = io.popen(command)
	local text = pipe:read("a")
	pipe:close()
	return text
end

local function write(path, text)
	local file = assert(io.open(path, "w"))
	file:write(text)
	file:close()
end

-- A root for version k of an app: this checkout by symbolic link, except
-- the app, which is a copy with edits k+1…n reverse-applied, newest first.
local function root(name, k)
	local app = Edits[name]
	local dir = string.format("%s/%s-v%d", ROOTS, name, k)
	sh("rm -rf " .. quote(dir) .. " && mkdir -p " .. quote(dir .. "/demo"))
	for entry in read("ls -A " .. quote(repo)):gmatch("[^\n]+") do
		if entry ~= "demo" and entry ~= ".git" then
			sh("ln -s " .. quote(repo .. "/" .. entry) .. " " .. quote(dir .. "/" .. entry))
		end
	end
	for entry in read("ls " .. quote(repo .. "/demo")):gmatch("[^\n]+") do
		if "demo/" .. entry ~= app.dir then
			sh("ln -s " .. quote(repo .. "/demo/" .. entry) .. " " .. quote(dir .. "/demo/" .. entry))
		end
	end
	sh("cp -R " .. quote(repo .. "/" .. app.dir) .. " " .. quote(dir .. "/" .. app.dir))
	for i = #app.edits, k + 1, -1 do
		sh("patch -s -R -p1 -d " .. quote(dir) .. " < " .. quote(repo .. "/" .. here .. "edits/" .. app.edits[i].patch .. ".patch"))
	end
	return dir
end

local function mac(dir, entry, name, extra)
	sh(string.format("cd %s && %s/lua-objc --capture=%s --width=%d --height=%d %s %s -AppleShowScrollBars WhenScrolling",
		quote(dir), quote(repo), quote(OUT .. "/" .. name), SIZE.width, SIZE.height, entry, extra or ""))
	print("mac     " .. name)
end

-- The UDID of an available simulator by name, booted.
local udids = {}
local function device(kind)
	if udids[kind] then return udids[kind] end
	local list = read("xcrun simctl list devices available")
	local udid
	for line in list:gmatch("[^\n]+") do
		local found = line:match("^%s*" .. DEVICES[kind]:gsub("[%(%)%-]", "%%%0") .. " %((%x+%-[%x%-]+)%)")
		if found then udid = found; break end
	end
	if not udid then error("capture: no simulator named " .. DEVICES[kind], 0) end
	os.execute("xcrun simctl boot " .. udid .. " 2>/dev/null")
	sh("xcrun simctl bootstatus " .. udid .. " -b >/dev/null")
	-- The status bar every capture shows: 9:41, full signal and battery.
	sh("xcrun simctl status_bar " .. udid .. " override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState discharging --batteryLevel 100")
	udids[kind] = udid
	return udid
end

local function iphone(dir, entry, name)
	local udid = device("iphone")
	os.execute("pkill -f lua-objc-packager 2>/dev/null")
	sh(string.format("(trap '' PIPE; %s/build/lua-objc-packager --root %s --port 8081 --entry %s >%s/build/reel-promo/packager.log 2>&1 &)",
		quote(repo), quote(dir), entry, quote(repo)))
	sh("for i in $(seq 50); do curl -sf " .. PACKAGER .. "/health >/dev/null && exit 0; sleep 0.2; done; exit 1")
	sh("xcrun simctl install " .. udid .. " " .. quote(repo .. "/build/ios/LuaRuntime.app"))
	sh(string.format("SIMCTL_CHILD_LUA_OBJC_APP=%s SIMCTL_CHILD_LUA_OBJC_PACKAGER=%s xcrun simctl launch --terminate-running-process %s org.luaobjc.host >/dev/null",
		entry, PACKAGER, udid))
	sh("sleep " .. SETTLE.host)
	sh("xcrun simctl io " .. udid .. " screenshot " .. quote(OUT .. "/" .. name .. ".png") .. " >/dev/null 2>&1")
	os.execute("pkill -f lua-objc-packager 2>/dev/null")
	print("iphone  " .. name)
end

-- Lua Studio on the iPad, bundled with version k of Todo and the
-- conversation that led to it.
local function studio(k, name)
	local udid = device("ipad")
	local overlay = string.format("%s/studio-v%d", OVERLAYS, k)
	local app = Edits.todo
	sh("rm -rf " .. quote(overlay) .. " && mkdir -p " .. quote(overlay .. "/demo") .. " " .. quote(overlay .. "/showcase"))
	sh("cp -R " .. quote(ROOTS .. "/todo-v" .. k .. "/" .. app.dir) .. " " .. quote(overlay .. "/" .. app.dir))
	write(overlay .. "/showcase/todo.lua", Conversation.showcase(app, k, repo .. "/" .. here .. "edits/"))
	sh("make -s ipad-simulator APP=studio OVERLAY=" .. quote(overlay) .. " >/dev/null")
	local bundle = repo .. "/build/ipad/iphonesimulator-arm64/LuaStudio.app"
	sh("xcrun simctl install " .. udid .. " " .. quote(bundle))
	-- Launched from the home screen, so the status bar has no back link.
	os.execute("xcrun simctl terminate " .. udid .. " org.luaobjc.ledger 2>/dev/null")
	sh("SIMCTL_CHILD_LUA_STUDIO_SHOWCASE=showcase/todo.lua xcrun simctl launch --terminate-running-process "
		.. udid .. " org.luaobjc.studio >/dev/null")
	sh("sleep " .. SETTLE.studio)
	sh("xcrun simctl io " .. udid .. " screenshot " .. quote(OUT .. "/" .. name .. ".png") .. " >/dev/null 2>&1")
	print("studio  " .. name)
end

-- An app bundled on its own for the iPad (no packager): its UIKit version.
local function ipad(dir, name)
	local udid = device("ipad")
	local slug = dir:match("[^/]+$")
	sh("make -s ipad-simulator APP=" .. slug .. " APP_DIR=" .. dir .. " >/dev/null")
	sh("xcrun simctl install " .. udid .. " " .. quote(repo .. "/build/ipad/iphonesimulator-arm64/" .. slug .. ".app"))
	-- Launched from the home screen, so the status bar has no back link.
	os.execute("xcrun simctl terminate " .. udid .. " org.luaobjc.studio 2>/dev/null")
	sh("xcrun simctl launch --terminate-running-process " .. udid .. " org.luaobjc." .. slug .. " >/dev/null")
	sh("sleep " .. SETTLE.studio)
	sh("xcrun simctl io " .. udid .. " screenshot " .. quote(OUT .. "/" .. name .. ".png") .. " >/dev/null 2>&1")
	print("ipad    " .. name)
end

local function main(...)
	local steps = {}
	for _, step in ipairs({ ... }) do steps[step] = true end
	if not next(steps) then steps = { mac = true, iphone = true, studio = true } end
	sh("mkdir -p " .. quote(OUT) .. " " .. quote(repo .. "/build/reel-promo"))
	local roots = {}
	for name, app in pairs(Edits) do
		roots[name] = {}
		for k = 0, #app.edits do roots[name][k] = root(name, k) end
	end
	if steps.mac then
		for name, app in pairs(Edits) do
			for k = 0, #app.edits do mac(roots[name][k], app.dir .. "/init.lua", name .. "-v" .. k) end
		end
		mac(repo, "apps/weather/init.lua", "weather", "--showcase")
	end
	if steps.iphone then
		sh("make -s ios-host ios-packager >/dev/null")
		for k = 0, #Edits.todo.edits do iphone(roots.todo[k], Edits.todo.dir, "todo-iphone-v" .. k) end
	end
	if steps.studio then
		ipad(Edits.ledger.dir, "ledger-ipad")
		for k = 0, #Edits.todo.edits do studio(k, "studio-v" .. k) end
	end
	return 0
end

local ok, status = pcall(main, table.unpack(arg or {}))
if not ok then
	io.stderr:write(tostring(status) .. "\n")
	os.exit(1)
end
os.exit(status)
