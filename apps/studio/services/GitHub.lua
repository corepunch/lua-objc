local GitHub = {}
GitHub.__index = GitHub
function GitHub.new(device)
	return setmetatable({device=device},GitHub)
end
function GitHub:request(method, path, token, body, done)
	if not token or token=="" then done(nil,"Connect your GitHub account first"); return end
	return self.device.request(method,path,token,body,function(result,err)
		if err then done(nil,err); return end
		done(result)
	end)
end
function GitHub:connect(token, done)
	return self:request("GET","/user",token,nil,function(user,err)
		if not user then done(nil,err); return end
		if type(user.login)~="string" or type(user.id)~="number" then done(nil,"GitHub returned an invalid account"); return end
		done(user)
	end)
end
function GitHub:repository(owner,name,done)
	return self:request("GET","/repos/"..owner.."/"..name,self.device.credentials.read(),nil,done)
end
function GitHub:create(owner,name,private,login,done)
	local path=owner:lower()==login:lower() and "/user/repos" or ("/orgs/"..owner.."/repos")
	return self:request("POST",path,self.device.credentials.read(),{name=name,private=private,auto_init=false},done)
end
function GitHub:link(versions, owner, name, repository, branch)
	if not repository or type(repository.full_name)~="string" or repository.full_name:lower()~=(owner.."/"..name):lower() then return nil,"GitHub returned a different repository" end
	if repository.permissions and repository.permissions.push==false then return nil,"This account cannot push to that repository" end
	return versions.repo:setRemote("origin","https://github.com/"..owner.."/"..name..".git",branch)
end
function GitHub:push(versions,author,done)
	local token=self.device.credentials.read()
	if not token or token=="" then done(nil,"Connect your GitHub account first"); return end
	local commit,err=versions:record("Publish from Lua Studio",author)
	if commit==nil then done(nil,err); return end
	return versions.repo:push("origin",{username="x-access-token",token=token},done)
end
return GitHub
