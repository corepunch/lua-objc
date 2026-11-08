-- ns.http: the one native HTTP request both platforms share
-- (src/shared/lua_async.m). Nothing here reaches the network: a refused
-- loopback port answers at once, and fetch is checked over a stubbed http.
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")

-- A port nothing listens on: the connection is refused before any byte moves.
local refused = "http://127.0.0.1:9/never"

local function wait(done)
	for _ = 1, 200 do
		if done() then return true end
		bridge._runLoopTick(0.01)
	end
	return done()
end

-- The request table is checked before anything is sent.
local function refuses(request, fragment, label)
	local ok, err = pcall(ns.http, request, function() end)
	t.expect(not ok and tostring(err):find(fragment, 1, true) ~= nil, label .. ": " .. tostring(err))
end
refuses({}, "http or https url", "a request needs a url")
refuses({url = "ftp://example.com/file"}, "http or https url", "only http and https are sent")
refuses({url = "file:///etc/hosts"}, "http or https url", "local files are not HTTP")
refuses({url = refused, method = 7}, "method must be a string", "the method is a string")
refuses({url = refused, headers = "Accept: */*"}, "headers must be a table", "headers are a table")
refuses({url = refused, headers = {Accept = 1}}, "map names to strings", "header values are strings")
refuses({url = refused, body = {a = 1}}, "body must be a string", "a body is already encoded")
t.expect(not pcall(ns.http, {url = refused}), "a request needs a completion")

-- No answer: done(nil, message), once.
local calls, response, message = 0, "unset", nil
local cancel = ns.http({url = refused, method = "post", body = "\0bytes\255"}, function(r, err)
	calls, response, message = calls + 1, r, err
end)
t.assertEqual(type(cancel), "function", "http returns a cancel function")
t.expect(wait(function() return calls > 0 end), "a refused connection answers")
t.assertEqual(response, nil, "no response when nothing answered")
t.expect(type(message) == "string" and message ~= "", "the failure carries a message")
bridge._runLoopTick(0.05)
t.assertEqual(calls, 1, "done runs exactly once")
cancel() -- cancelling a finished request does nothing

-- A cancelled request calls nothing.
local cancelledCalls = 0
local stop = ns.http({url = "http://10.255.255.1/slow", timeout = 5}, function()
	cancelledCalls = cancelledCalls + 1
end)
stop()
for _ = 1, 20 do bridge._runLoopTick(0.01) end
t.assertEqual(cancelledCalls, 0, "a cancelled request never calls done")

-- fetch is the coroutine GET over http: 2xx returns the body, anything else
-- raises, as no answer does.
local http = ns.http
-- The native request always answers later, from the run loop; the stub keeps
-- `done` and answers once the coroutine has yielded.
local function fetchWith(answer)
	local pending
	ns.http = function(request, done)
		t.assertEqual(request.url, "https://example.com/data", "fetch asks for its url")
		t.assertEqual(request.method, nil, "fetch is a GET")
		pending = done
		return function() end
	end
	local result
	ns.async(function() result = {pcall(ns.fetch, "https://example.com/data")} end)
	ns.http = http
	t.expect(pending ~= nil and result == nil, "fetch waits for the answer")
	pending(answer.response, answer.err)
	return result
end
local ok = fetchWith({response = {status = 200, headers = {}, body = "{\"a\":1}"}})
t.expect(ok[1] and ok[2] == "{\"a\":1}", "a 2xx answer returns its body")
local missing = fetchWith({response = {status = 404, headers = {}, body = "not found"}})
t.expect(not missing[1] and tostring(missing[2]):find("HTTP 404", 1, true), "a 404 raises with its status")
local offline = fetchWith({err = "The Internet connection appears to be offline."})
t.expect(not offline[1] and tostring(offline[2]):find("offline", 1, true), "no answer raises its message")
t.expect(not pcall(ns.fetch, "https://example.com/data"), "fetch outside a coroutine is an error")

os.exit(t.summary() and 0 or 1)
