local Model = require("data.model")
local Accounts, Account = Model:extend("studioGitHub", {primaryKey = "id"})
function Accounts.current()
	return Accounts:find("github") or Accounts:create({id="github",login="",name="",email="",owner="",repository="",private=true,linked=false,branch="main"})
end
function Account:authenticate(user)
	if type(user) ~= "table" or type(user.login) ~= "string" or not user.login:match("^[%w%-]+$")
		or type(user.id) ~= "number" then return nil, "GitHub returned an invalid account" end
	return self:update({login=user.login,name=user.name or user.login,
		email=user.email or (tostring(user.id) .. "+" .. user.login .. "@users.noreply.github.com")})
end
function Account:target(owner, repository, private)
	if type(owner) ~= "string" or #owner > 39 or not owner:match("^[%w][%w%-]*$") or owner:sub(-1)=="-" then return nil,"Enter a GitHub user or organization name" end
	if type(repository) ~= "string" or #repository > 100 or not repository:match("^[%w_.%-]+$") or repository=="." or repository==".." then return nil,"Use a repository name with letters, numbers, dots, hyphens or underscores" end
	return self:update({owner=owner,repository=repository,private=private==true,linked=false})
end
function Account:validateBranch()
	if type(self.branch)~="string" or #self.branch>80 or not self.branch:match("^[%w_%-]+$") then return nil,"Use a GitHub branch name with letters, numbers, hyphens or underscores" end
	return true
end
function Account:author()
	if self.login=="" then return nil,"Connect your GitHub account first" end
	if not self.name:match("%S") or self.name:find("[\r\n]") or not self.email:match("^[^%s<>@]+@[^%s<>@]+$") then return nil,"Enter a commit author name and email" end
	return {name=self.name,email=self.email}
end
function Account:url()
	if self.linked then return "https://github.com/" .. self.owner .. "/" .. self.repository .. "/tree/" .. self.branch end
end
return Accounts
