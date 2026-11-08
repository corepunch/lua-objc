-- The account page of an app with a `<Backend>` (docs/backend.md): who is
-- signed in, and the forms to register, sign in and sign out. The framework
-- owns the route; the app owns the view, as every page's view is the app's.
--
--   -- routes.lua
--   account = require("data.account").route({view = "pages/Account"}),
--
-- The view reads `anonymous`, `email`, `busy` (an account request is out),
-- `failure` (what the server refused) and `errors` (what the page refused
-- before sending), and names the actions `setEmail`, `setPassword`,
-- `register`, `signIn` and `signOut`. The password lives in the page while
-- it is typed and is dropped once sent; it never reaches the store.
local Model = require("data.model")
local Routes = require("data.routes")

local Account = {}

-- Appwrite's own minimum for a password.
Account.minimumPassword = 8

local function backend()
	return Model.backend or error("the account page needs an app with a <Backend>", 0)
end

local function credentials(page)
	local email = (page.email or ""):match("^%s*(.-)%s*$")
	Routes.assert(email:match("^[^@%s]+@[^@%s]+%.[^@%s]+$"), "Enter an email address.")
	Routes.assert(#(page.password or "") >= Account.minimumPassword,
		"A password has at least " .. Account.minimumPassword .. " characters.")
	local password = page.password
	page.password = nil
	return email, password
end

function Account.route(spec)
	assert(type(spec) == "table" and type(spec.view) == "string", "Account.route needs the app's view")
	return {
		view = spec.view,
		-- Typing changes nothing on screen, so the page is not drawn again.
		queries = {setEmail = true, setPassword = true},
		data = function(page, state)
			local service = backend()
			local user = service.account.user
			return {
				signedIn = user ~= nil,
				anonymous = user == nil or user.anonymous,
				email = user and user.email or "",
				draft = page.email or "",
				busy = service.accountBusy == true,
				failure = state.error,
			}
		end,
		setEmail = function(page, email) page.email = email end,
		setPassword = function(page, password) page.password = password end,
		register = function(page)
			local email, password = credentials(page)
			backend():register(email, password)
		end,
		signIn = function(page)
			local email, password = credentials(page)
			backend():signIn(email, password)
		end,
		signOut = function() backend():signOut() end,
	}
end

return Account
