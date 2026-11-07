local t = require("TestKit")
local Model = require("data.model")
local Accounts = require("apps.studio.models.GitHub")
local Controller = require("apps.studio.controllers.GitHubController")
local Versions = require("apps.studio.services.Versions")
local store = require("apps.studio.Store")()
Model.bind(store)
local account = Accounts.current()
t.expect(not account:target("../bad","repo",true),"owner traversal is rejected")
t.expect(not account:target("octocat","../bad",true),"repository traversal is rejected")
t.expect(not account:target("octocat","..",true),"parent directory cannot be a repository")
t.expect(account:target("octocat","hello-world",true),"normal target accepted")
t.expect(not account:author(),"publishing requires a connected account")
account:update({branch="bad branch"});t.expect(not account:validateBranch(),"invalid target branches are rejected")
account:update({branch="main"})
local token, pending, method, path, body, remote, pushed, committed, author, cancelled
local device = {credentials = {read=function() return token end,save=function(value) token=value; return true end,clear=function() token=nil; return true end},
	request=function(m,p,key,b,callback)
		method,path,body,pending=m,p,b,callback
		t.expect(key~="","requests authenticate without URL credentials")
		return function() cancelled=true end
	end}
local repo = {remotes=function() return remote and {{name="origin",url=remote}} or {} end,
	setRemote=function(_,name,url) remote=url; return true end,
	add=function() return true end,status=function() return {{index="modified"}} end,
	commit=function(_,message,identity) committed=message;author=identity;return "commit" end,
	push=function(_,name,credentials,callback)
		pushed={name=name,credentials=credentials,callback=callback}
		return {cancel=function() cancelled=true end}
	end}
local root = {store=store,activeProject={id="Example"},versions=setmetatable({repo=repo},Versions),actions={},
	session={saveDrafts=function() return true end},chat={stop=function() end},render=function() end,
	sheets={update=function() end}}
function root:showSheet(kind,data) self.sheetKind,self.sheetData=kind,data end
local controller = Controller.new(root,device)
controller:show()
t.assertEqual(root.sheetKind,"GitHub","GitHub has an etlua sheet")
t.expect(controller:data().private,"new repositories default to private")
controller:edit("tokenDraft"," fixture ")
t.expect(controller:connect(),"connect starts asynchronously")
t.assertEqual(path,"/user","authenticate against GitHub profile")
t.assertEqual(method,"GET","profile uses GET")
t.expect(not controller:connect(),"a second operation cannot start concurrently")
pending({login="octocat",id=1,name="Octo Cat"})
t.assertEqual(token,"fixture","only a validated token is saved")
t.assertEqual(controller.tokenDraft,"","the form clears the key after saving")
t.assertEqual(account.email,"1+octocat@users.noreply.github.com","default author avoids disclosing an unavailable email")
controller:edit("owner","octocat"); controller:edit("repository","Example")
t.expect(controller:link(true),"create starts")
t.assertEqual(path,"/user/repos","personal repository endpoint")
t.expect(body.private and body.auto_init==false,"new GitHub repository starts private and empty")
pending({full_name="octocat/Example",private=true,permissions={push=true}})
t.assertEqual(remote,"https://github.com/octocat/Example.git","origin never contains credentials")
t.expect(account.linked,"created repository is linked to the local libgit2 repository")
t.assertEqual(account:url(),"https://github.com/octocat/Example/tree/main","project is viewable on GitHub")
t.expect(controller:publish(),"publish starts")
t.assertEqual(author.name,"Octo Cat","GitHub author identity reaches libgit2 commits")
t.assertEqual(pushed.name,"origin","libgit2 pushes the linked origin")
t.assertEqual(pushed.credentials.token,"fixture","the token is passed in memory to libgit2")
t.expect(controller.busy,"busy remains until libgit2 completes")
pushed.callback(true)
t.expect(not controller.busy and controller.message:find("Published",1,true),"only completed pushes report published")
controller:edit("owner","organization")
t.expect(not account.linked,"editing a target invalidates the previous link")
controller:link(true)
t.assertEqual(path,"/orgs/organization/repos","organization repositories use their own endpoint")
pending({full_name="someone/else",private=true})
t.expect(not account.linked,"a mismatched repository is not adopted")
controller:link(false); pending({full_name="organization/Example",permissions={push=false}})
t.expect(not account.linked,"read-only repository cannot be linked for publishing")
controller:connect(); local stale=pending; controller:cancel()
t.expect(cancelled and not controller.busy,"cancel releases the visible operation")
controller:connect(); stale({login="intruder",id=2})
t.expect(controller.busy and account.login=="octocat","late responses cannot change a newer operation")
t.assertEqual(token,"fixture","cancelled connection callbacks cannot replace Keychain credentials")
pending(nil,"Bad credentials")
t.expect(not controller.busy and controller.message=="Bad credentials","authentication failure stays actionable")
controller:disconnect()
t.expect(token==nil and account.login=="","disconnect clears Keychain access")
local xml = require("ui.xml")
t.expect(xml.describeFile("apps/studio/views/sheets/GitHub.etlua",controller:data()).source:find('action="publishGitHub"',1,true),"publishing is wired in etlua")
os.exit(t.summary() and 0 or 1)
