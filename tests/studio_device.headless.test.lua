local t = require("TestKit")
local Device = require("apps.studio.services.Device")
local values, callback, last, cancelled = {}, nil, nil, nil
local ns = {
	Credentials = {get=function(id) return values[id] end, set=function(id,value) values[id]=value; return true end,
		remove=function(id) values[id]=nil; return true end},
	_jsonEncode=function(value) return value end,
	json_parse=function(value) if value=="broken" then error("decode") end; return value end,
	_httpRequest=function(url,headers,body,done,method) last={url=url,headers=headers,body=body,method=method}; callback=done; return 7 end,
	_cancelRequest=function(id) cancelled=id end,
}
local device=Device.new(ns)
t.expect(not device.credentials.save("  "),"blank keys are rejected")
t.expect(device.credentials.save(" fixture-key "),"a key is saved through the credential store")
t.assertEqual(values.openrouter,"fixture-key","keys are trimmed")
local response, message
local cancel=device.transport({model="provider/model"},device.credentials.read(),function(result,err) response,message=result,err end)
t.assertEqual(last.url,"https://openrouter.ai/api/v1/chat/completions","the agent uses the documented HTTPS endpoint")
t.assertEqual(last.headers.Authorization,"Bearer fixture-key","authorization stays in the request header")
t.assertEqual(last.body.model,"provider/model","the selected model reaches transport")
callback({choices={}},nil,200); t.expect(response~=nil and message==nil,"valid provider JSON reaches the agent")
callback("broken",nil,200); t.expect(message:find("invalid JSON",1,true),"invalid JSON is reported")
callback({error={message="Unauthorized"}},nil,401); t.expect(message:find("401: Unauthorized",1,true),"HTTP errors preserve actionable provider detail")
callback(nil,"offline",0); t.assertEqual(message,"offline","network errors are reported")
cancel(); t.assertEqual(cancelled,7,"cancellation targets the native request")
device.credentials.clear(); t.assertEqual(device.credentials.read(),nil,"credentials can be removed")
device.github.credentials.save("github-fixture")
t.assertEqual(device.github.credentials.read(),"github-fixture","GitHub has a separate Keychain entry")
local cancelGitHub=device.github.request("GET","/user",device.github.credentials.read(),nil,function(result,err) response,message=result,err end)
t.assertEqual(last.url,"https://api.github.com/user","GitHub authentication goes only to its HTTPS API")
t.assertEqual(last.method,"GET","the HTTP bridge accepts the request method")
t.assertEqual(last.headers.Authorization,"Bearer github-fixture","GitHub token stays in the Authorization header")
callback({login="octocat",id=1},nil,200);t.assertEqual(response.login,"octocat","profile JSON reaches the service")
callback({message="Bad credentials"},nil,401);t.expect(message:find("401",1,true),"GitHub authentication failures include status")
cancelGitHub();t.assertEqual(cancelled,7,"GitHub requests can be cancelled")
device.github.credentials.clear();t.assertEqual(device.github.credentials.read(),nil,"GitHub token can be removed")
os.exit(t.summary() and 0 or 1)
