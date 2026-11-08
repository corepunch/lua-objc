-- A recording Appwrite transport for headless tests: no network. Each request
-- is kept in `sent`; each answer is taken from `answers` in order and given
-- at once, as ns.http's `done` would later: {status, headers, body}, where a
-- table body is encoded to JSON, or {err = message} for no answer.
local Json = require("data.appwrite.json")
local ns = require("AppKit")
local Client = require("data.appwrite.client")

local Mock = {}

function Mock.new(options)
	options = options or {}
	-- `mock.hold = true` keeps requests waiting until `mock.step()` answers the
	-- oldest, as a real request answers later from the run loop.
	local mock = {sent = {}, answers = {}, cancelled = 0, hold = false, held = {}}
	local function answer(request, done)
		local answer = table.remove(mock.answers, 1)
		assert(answer, "no answer queued for " .. request.method .. " " .. request.url)
		if answer.err then
			done(nil, answer.err)
		else
			local body = answer.body
			if type(body) == "table" then body = Json.encode(body) end
			done({status = answer.status or 200, headers = answer.headers or {}, body = body or ""})
		end
	end
	function mock.http(request, done)
		table.insert(mock.sent, request)
		if mock.hold then table.insert(mock.held, {request = request, done = done})
		else answer(request, done) end
		return function() mock.cancelled = mock.cancelled + 1 end
	end
	-- Answers the oldest waiting request; false when none waits.
	function mock.step()
		local waiting = table.remove(mock.held, 1)
		if not waiting then return false end
		answer(waiting.request, waiting.done)
		return true
	end
	function mock.drain()
		while mock.step() do end
	end
	function mock.answer(answer) table.insert(mock.answers, answer) end
	function mock.last() return mock.sent[#mock.sent] end
	mock.client = Client.new({
		endpoint = options.endpoint or "https://fra.cloud.appwrite.io/v1/",
		project = options.project or "lua-objc-dev",
		http = mock.http,
		decode = ns.json_parse,
	})
	return mock
end

-- A secret store in memory, standing in for the Keychain.
function Mock.secrets(initial)
	local store = {value = initial, writes = 0}
	function store.read() return store.value end
	function store.write(value) store.value = value; store.writes = store.writes + 1; return true end
	function store.remove() store.value = nil; return true end
	return store
end

return Mock
