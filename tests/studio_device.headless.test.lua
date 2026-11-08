local t = require("TestKit")
local Device = require("apps.studio.services.Device")
local values, callback, last, cancelled = {}, nil, nil, nil
local ns = {
	Credentials = {get=function(id) return values[id] end, set=function(id,value) values[id]=value; return true end,
		remove=function(id) values[id]=nil; return true end},
	_jsonEncode=function(value) return value end,
	json_parse=function(value) if value=="broken" then error("decode") end; return value end,
	http=function(request,done) last=request; callback=done; local id=7; return function() cancelled=id end end,
}
-- The service hands the native answer {status, headers, body} on unchanged.
local function answer(body,status) callback({status=status,headers={},body=body}) end
local device=Device.new(ns)
t.expect(not device.credentials.save("  "),"blank keys are rejected")
t.expect(device.credentials.save(" fixture-key "),"a key is saved through the credential store")
t.assertEqual(values.openrouter,"fixture-key","keys are trimmed")
local response, message
local cancel=device.transport({model="provider/model"},device.credentials.read(),function(result,err) response,message=result,err end)
t.assertEqual(last.url,"https://openrouter.ai/api/v1/chat/completions","the agent uses the documented HTTPS endpoint")
t.assertEqual(last.headers.Authorization,"Bearer fixture-key","authorization stays in the request header")
t.assertEqual(last.method,"POST","the agent posts its request")
t.assertEqual(last.body.model,"provider/model","the selected model reaches transport")
answer({choices={}},200); t.expect(response~=nil and message==nil,"valid provider JSON reaches the agent")
answer("broken",200); t.expect(message:find("invalid JSON",1,true),"invalid JSON is reported")
answer({error={message="Unauthorized"}},401); t.expect(message:find("401: Unauthorized",1,true),"HTTP errors preserve actionable provider detail")
callback(nil,"offline"); t.expect(message:find("offline",1,true) and message:find("Settings",1,true),"network errors explain how to recover")
for _,sample in ipairs({
	{status=401,body={error={message="Unauthorized"}},hint="API key"},
	{status=402,body={error={message="Insufficient credits"}},hint="free model"},
	{status=404,body={error="Model unavailable"},hint="available provider/model"},
	{status=429,body="broken",hint="Try again later"},
	{status=503,body={error={message="Provider unavailable"}},hint="another model"},
}) do
	answer(sample.body,sample.status)
	t.expect(response==nil and message:find(tostring(sample.status),1,true),"failed provider responses preserve their HTTP status")
	t.expect(message:find(sample.hint,1,true),"provider failure gives a recovery action")
end
cancel(); t.assertEqual(cancelled,7,"cancellation targets the native request")
device.credentials.clear(); t.assertEqual(device.credentials.read(),nil,"credentials can be removed")
device.github.credentials.save("github-fixture")
t.assertEqual(device.github.credentials.read(),"github-fixture","GitHub has a separate Keychain entry")
local cancelGitHub=device.github.request("GET","/user",device.github.credentials.read(),nil,function(result,err) response,message=result,err end)
t.assertEqual(last.url,"https://api.github.com/user","GitHub authentication goes only to its HTTPS API")
t.assertEqual(last.method,"GET","the HTTP bridge accepts the request method")
t.assertEqual(last.body,nil,"a GET sends no body")
t.assertEqual(last.headers.Authorization,"Bearer github-fixture","GitHub token stays in the Authorization header")
answer({login="octocat",id=1},200);t.assertEqual(response.login,"octocat","profile JSON reaches the service")
answer({message="Bad credentials"},401);t.expect(message:find("401",1,true),"GitHub authentication failures include status")
cancelGitHub();t.assertEqual(cancelled,7,"GitHub requests can be cancelled")
device.github.credentials.clear();t.assertEqual(device.github.credentials.read(),nil,"GitHub token can be removed")
os.exit(t.summary() and 0 or 1)
