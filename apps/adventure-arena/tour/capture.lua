-- Capture plan for the tour's screenshots (models/Onboarding.lua), run by
-- `make adventure-arena-tour-captures` in the iPhone Simulator: tour/init.lua
-- starts the app and calls Plan.run, which opens the reader on a story,
-- plays the moves each tour page talks about, and asks tour/capture.sh for a
-- screenshot of each state in light and dark.
--
-- The reader is captured on the phone because that is where its keyboard
-- and suggestion bar live; `simctl io screenshot` sees them, a capture from
-- inside the app does not. The plan and the script talk through one file
-- in the app's temporary folder: the plan writes a request there and waits
-- until the script has served it and removed it.
--
-- Every image is one band of the screen, full width, with the proportions
-- of the tour's image box, scaled to BOX.scale times the box.
local ns = require("ns")

local Plan = {}

-- BOX matches GUIDE in views/Onboarding.etlua;
-- tests/adventure_arena_onboarding.test.lua checks every image against it.
Plan.BOX = { width = 300, height = 252, scale = 3 }

-- An all-ages Arena Original: its opening is short, and every scene has
-- words the reader can touch.
local STORY = "books.wondertown"

-- One shot per guide page, named by its id. `commands` are played from the
-- title page; `top` is where the band starts, in points from the top of
-- DEVICE's screen (tour/capture.sh), chosen so that no line of type is cut.
-- `scroll` is the end of the page shown; `typed` is left in the command
-- field with the keyboard up.
Plan.SHOTS = {
	{ name = "welcome", commands = {}, scroll = "top", top = 130 },
	{ name = "interactive", commands = { "take broom", "look under workbench", "take oil can" }, scroll = "bottom", top = 404 },
	{ name = "read", commands = { "north" }, scroll = "bottom", top = 370 },
	{ name = "play", commands = { "take broom" }, scroll = "bottom", typed = "t", top = 306 },
}

local SETTLE = { launch = 1, page = 1, keyboard = 1.5, appearance = 1.5 }

local function request(line)
	local path = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "") .. "/adventure-arena-tour/request"
	local file = assert(io.open(path .. ".new", "w"))
	file:write(line, "\n")
	file:close()
	assert(os.rename(path .. ".new", path))
	while true do
		local pending = io.open(path, "r")
		if not pending then return end
		pending:close()
		ns.sleep(0.1)
	end
end

local function show(session, shot)
	session:show(STORY, true)
	for _, command in ipairs(shot.commands) do session:submitCommand(command) end
	-- The page as it stands once its type has finished printing.
	session:finishTyping()
	session:renderTranscript()
	session.refs.transcriptScroll:scrollTo(shot.scroll, false)
	if shot.typed then
		-- As a reader does it: the keyboard first, then the letters.
		require("UIKitNative")._focus(session.refs.input)
		ns.sleep(SETTLE.keyboard)
		session.refs.input.text = shot.typed
		session:updateComposer(shot.typed)
		ns.sleep(SETTLE.keyboard)
	end
	ns.sleep(SETTLE.page)
end

function Plan.run(app)
	local session = app.sessionController
	ns.sleep(SETTLE.launch)
	for _, appearance in ipairs({ "light", "dark" }) do
		request("appearance " .. appearance)
		ns.sleep(SETTLE.appearance)
		for _, shot in ipairs(Plan.SHOTS) do
			show(session, shot)
			request(string.format("shot %s-%s %d %d %d %d", shot.name, appearance,
				shot.top, Plan.BOX.width, Plan.BOX.height, Plan.BOX.scale))
			session:close()
			ns.sleep(SETTLE.page)
		end
	end
	request("done")
end

return Plan
