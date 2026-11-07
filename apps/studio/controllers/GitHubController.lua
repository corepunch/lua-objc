local Model = require("data.model")
local Accounts = require("apps.studio.models.GitHub")
local Service = require("apps.studio.services.GitHub")
local GitHub = {}
GitHub.__index = GitHub
function GitHub.new(root, device)
	return setmetatable({root=root,service=Service.new(device),busy=false},GitHub)
end
function GitHub:refresh(message)
	self.message=message or ""
	if self.root.sheetKind=="GitHub" then
		local data=self:data(); data.actions=self.root.actions
		self.root.sheetData=data; self.root.sheets:update(data)
	else self.root.status=self.message; self.root:render() end
end
function GitHub:data()
	local row=Accounts.current()
	return {title="GitHub",tokenDraft=self.tokenDraft or "",hasToken=self.service.device.credentials.read()~=nil,
		login=row.login,name=row.name,email=row.email,owner=row.owner,repository=row.repository,
		private=row.private,branch=row.branch,linked=row.linked,url=row:url(),busy=self.busy,message=self.message or ""}
end
function GitHub:show()
	local row=Accounts.current()
	local project=self.root.activeProject
	if self.project~=project.id then
		self.project=project.id
		local owner,name,branch
		for _,remote in ipairs(self.root.versions.repo:remotes()) do
			if remote.name=="origin" then owner,name=remote.url:match("^https://github%.com/([%w%-]+)/([%w_.%-]+)%.git$"); branch=remote.branch end
		end
		row:target(owner or row.login,name or project.id,true)
		-- An account may not have been connected yet; the empty owner is a draft.
		if not owner and row.owner=="" then row:update({repository=project.id}) end
		row:update({linked=owner~=nil,branch=branch or "main"})
	end
	self.tokenDraft=""
	self.root:showSheet("GitHub",self:data())
end
function GitHub:edit(field,value)
	if self.busy then return end
	if field=="tokenDraft" then self.tokenDraft=value
	else
		local row=Accounts.current(); row:update({[field]=value})
		if field=="owner" or field=="repository" or field=="branch" then row:update({linked=false}) end
	end
	self:refresh(self.message)
end
function GitHub:start(message,operation)
	if self.busy then return nil,"A GitHub operation is already running" end
	self.generation=(self.generation or 0)+1
	local generation=self.generation
	local function current() return self.generation==generation end
	self.busy=true; self:refresh(message)
	local complete=false
	local function done(ok,err)
		if not current() then return end
		complete=true; self.pending=nil; self.busy=false
		self:refresh(ok and "Ready" or tostring(err))
	end
	local ok,pending,err=pcall(operation,done,current)
	if not ok then done(nil,pending); return nil,pending end
	if not pending and not complete then done(nil,err or "Could not start GitHub operation"); return nil,err end
	if not complete then self.pending=pending end
	return true
end
function GitHub:connect()
	local token=self.tokenDraft
	if not token or not token:match("%S") then token=self.service.device.credentials.read() end
	if type(token)~="string" or not token:match("%S") then self:refresh("Enter a GitHub personal access token"); return nil end
	token=token:match("^%s*(.-)%s*$")
	return self:start("Connecting to GitHub…",function(done,current)
		return self.service:connect(token,Model.bound(self.root.store,function(user,err)
			if not current() then return end
			if user then
				local saved,saveError=self.service.device.credentials.save(token)
				if not saved then done(nil,saveError); return end
				local row=Accounts.current(); local oldLogin=row.login
				local valid,accountError=row:authenticate(user)
				if not valid then done(nil,accountError); return end
				if row.owner=="" or row.owner==oldLogin then row:update({owner=row.login}) end
				self.tokenDraft=""
			end
			done(user,err)
		end))
	end)
end
function GitHub:link(create)
	local row=Accounts.current()
	local author,err=row:author()
	if not author then self:refresh(err); return nil end
	local valid; valid,err=row:validateBranch()
	if not valid then self:refresh(err); return nil end
	local ok; ok,err=row:target(row.owner,row.repository,row.private)
	if not ok then self:refresh(err); return nil end
	local owner,name,private,versions,branch=row.owner,row.repository,row.private,self.root.versions,row.branch
	return self:start(create and "Creating repository…" or "Checking repository…",function(done,current)
		local callback=Model.bound(self.root.store,function(repository,detail)
			if not current() then return end
			if not repository then done(nil,detail); return end
			local linked,why=self.service:link(versions,owner,name,repository,branch)
			if linked then Accounts.current():update({linked=true,private=repository.private==true}) end
			done(linked,why)
		end)
		if create then return self.service:create(owner,name,private,row.login,callback) end
		return self.service:repository(owner,name,callback)
	end)
end
function GitHub:publish()
	local row=Accounts.current()
	if not row.linked then self:refresh("Create or link the repository first"); return nil end
	local author,err=row:author()
	if not author then self:refresh(err); return nil end
	local saved; saved,err=self.root.session:saveDrafts()
	if not saved then self:refresh(err); return nil end
	self.root.chat:stop()
	return self:start("Publishing commits…",function(done,current)
		return self.service:push(self.root.versions,author,Model.bound(self.root.store,function(ok,detail)
			if not current() then return end
			done(ok,detail)
			if ok then self:refresh("Published. Open the repository on GitHub to see your project and commit history.") end
		end))
	end)
end
function GitHub:disconnect()
	if self.busy then return end
	local ok,err=self.service.device.credentials.clear()
	if ok then Accounts.current():update({login="",name="",email=""}); self.tokenDraft="" end
	self:refresh(ok and "Saved GitHub token removed." or err)
end
function GitHub:cancel()
	if not self.pending then return end
	self.generation=(self.generation or 0)+1
	if type(self.pending)=="function" then self.pending() else self.pending:cancel() end
	self.pending=nil; self.busy=false; self:refresh("Cancelled. Your local commits remain on this iPad.")
end
return GitHub
