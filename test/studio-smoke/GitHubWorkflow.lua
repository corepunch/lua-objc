-- Opt-in live test. The caller supplies a credential and an existing private
-- verification repository; every run publishes to its own new branch.
local Accounts = require("apps.studio.models.GitHub")
local Workflow = {}
function Workflow.prepare(app)
	local ns = app.ns
	local previous = ns._documentRead("github-payload.json")
	if previous then
		local data = ns.json_parse(previous)
		if ns._documentExists(data.projectId .. "/project.lua") then assert(app:openProject(data.projectId));return end
	end
	app:showNewProject()
	ns._textFieldTestInput(app.sheets.template.refs.projectName, "Git Workflow Proof")
	assert(app.actions.createProject())
	app.actions.showCode();app:selectFile("views/pages/Main.etlua")
	local source = app.model:source("demo/playground/views/pages/Main.etlua"):gsub("My App", "Published Workflow")
	ns._textEditorTestInput(app.refs.sourceCode, source)
	assert(app.actions.saveSource());assert(app.actions.reloadPreview())
	assert(app:commitProject("Prepare verification project"))
	assert(ns._documentWrite("github-payload.json", ns._jsonEncode({projectId=app.activeProject.id,
		head=app.versions.repo:head().id})))
end
function Workflow.run(app, scenario, finish)
	local ns = app.ns
	if scenario ~= "github-live" then
		local evidence = assert(ns._documentRead("github-evidence.json"))
		local data = ns.json_parse(evidence)
		assert(app:openProject(data.projectId))
		local remote = app.versions.repo:remotes()[1]
		assert(remote and remote.branch == data.branch, "GitHub target did not survive relaunch")
		assert(app.device.github.credentials.read(), "GitHub Keychain token did not survive relaunch")
		assert(app.versions.repo:head().id == data.head, "published Git history did not survive relaunch")
		if scenario == "github-live-delete" then
			app.actions.showDeleteProject();ns.dismiss();assert(app:deleteProject(app.activeProject.id))
			assert(not ns._documentExists(data.projectId), "published local project was not deleted")
			assert(app.device.github.credentials.clear())
			app.github.service:request("GET", "/repos/" .. data.repository .. "/commits/" .. data.branch,
				os.getenv("STUDIO_GITHUB_TEST_TOKEN"), nil, function(commit, err)
					finish(commit and commit.sha == data.head, err or "Remote changed after local deletion")
				end)
		else
			app.actions.showGitHub()
			local refresh, finished = app.github.refresh, false
			app.github.refresh = function(controller, message)
				refresh(controller, message)
				if controller.busy or finished then return end
				finished = true
				local row = Accounts.current()
				if row.login == "" then finish(false, message);return end
				controller:edit("name", "Lua Studio")
				controller:edit("email", "studio@lua-objc.local")
				refresh(controller, "Reconnected with the saved token. Project, GitHub destination and commit history are intact.")
				app.sheets.template.refs.githubScroll:scrollTo("bottom", false)
				finish(true)
			end
			assert(app.actions.connectGitHub())
		end
		return
	end
	local branch = assert(os.getenv("STUDIO_GITHUB_TEST_BRANCH"))
	local payload = ns.json_parse(assert(ns._documentRead("github-payload.json"), "Prepare the reviewable demo before publishing"))
	assert(app:openProject(payload.projectId))
	assert(app.versions.repo:head().id == payload.head, "The prepared payload changed before publishing")
	app.actions.showGitHub()
	ns._textFieldTestInput(app.sheets.template.refs.githubToken, assert(os.getenv("STUDIO_GITHUB_TEST_TOKEN")))
	local refresh, stage = app.github.refresh, "connect"
	app.github.refresh = function(controller, message)
		refresh(controller, message)
		if controller.busy or stage == "finished" then return end
		local ok, err = xpcall(function()
			local row = Accounts.current()
			if stage == "connect" then
				assert(row.login ~= "", message)
				stage = "setup"
				controller:edit("name", "Lua Studio")
				controller:edit("email", "studio@lua-objc.local")
				ns._textFieldTestInput(app.sheets.template.refs.githubOwner, "corepunch")
				ns._textFieldTestInput(app.sheets.template.refs.githubRepository, assert(os.getenv("STUDIO_GITHUB_TEST_REPOSITORY")))
				ns._textFieldTestInput(app.sheets.template.refs.githubBranch, branch)
				stage = "link";assert(app.actions.linkGitHubRepository())
			elseif stage == "link" then
				assert(row.linked, message)
				stage = "push";assert(app.actions.publishGitHub())
			elseif stage == "push" and message ~= "Ready" then
				assert(message:find("Published.", 1, true), message)
				stage = "verify"
				local head, repository, url = app.versions.repo:head().id, row.owner .. "/" .. row.repository, row:url()
				controller.service:request("GET", "/repos/" .. repository .. "/commits/" .. branch,
					controller.service.device.credentials.read(), nil, function(commit, detail)
						stage = "finished"
						if not commit or commit.sha ~= head then finish(false, detail or "GitHub commit differs from local HEAD");return end
						assert(ns._documentWrite("github-evidence.json", ns._jsonEncode({passed=true, head=head,
							branch=branch,repository=repository,url=url,projectId=app.activeProject.id})))
						app.sheets.template.refs.githubScroll:scrollTo("bottom", false)
						finish(true)
					end)
			end
		end, debug.traceback)
		if not ok then stage = "finished";finish(false, err) end
	end
	assert(app.actions.connectGitHub())
end
return Workflow
