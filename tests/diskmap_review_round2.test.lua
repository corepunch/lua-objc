_G.__headless = true
local t = require('TestKit')
local ns = require('AppKit')
local bridge = require('AppKitNative')
local Model = require('apps.diskmap.Model')
local Mock = require('apps.diskmap.services.Mock')
local Root = require('apps.diskmap.Controller')
local Owners = require('apps.diskmap.services.Owners')
local System = require('apps.diskmap.services.System')
local Worktrees = require('apps.diskmap.models.Worktrees')

for _, pair in ipairs({{'repository','repositories'},{'directory','directories'},{'entry','entries'},
	{'key','keys'},{'cache','caches'},{'process','processes'},{'match','matches'},{'status','statuses'},
	{'more repository','more repositories'}}) do
	for _, count in ipairs({0,2,'1,234'}) do t.assertEqual(Model.plural(count, pair[1]), count .. ' ' .. pair[2], 'plural count and noun') end
	for _, count in ipairs({1,'1',1.0}) do t.assertEqual(Model.plural(count, pair[1]), count .. ' ' .. pair[1], 'one stays singular') end
end

local launches = {}
for name, identifier in pairs({codex='com.openai.codex',claude='com.anthropic.claudefordesktop',xcode='com.apple.dt.Xcode',docker='com.docker.docker'}) do
	t.expect(Owners.open(name, function(id) table.insert(launches,id); return true end), 'known owner opens')
	t.assertEqual(launches[#launches], identifier, 'owner uses stable bundle identifier')
end
local calls = #launches
local ok, message = Owners.open('unexpected', function() table.insert(launches,'wrong'); return true end)
t.expect(not ok and message:find('Unsupported',1,true), 'unknown owner reports unsupported')
t.assertEqual(#launches,calls,'unknown owner never launches another tool')
ok,message = Owners.open('codex',function() return false end)
t.expect(not ok and message:find('installed',1,true),'unavailable owner reports actionable error')
local execute, command = os.execute
os.execute = function(value) command=value; return true end
System.openOwner('codex')
os.execute = execute
t.expect(command:find('open -b',1,true) and command:find('com.openai.codex',1,true),'system integration uses bundle launch')

local service = Mock.new()
local app = Root.new(service)
local window = app:createWindow()
app.scan:start()
window.size = ns.Size(950,580); window:layout()
app:show('kinds'); app.page.actions.showInstallers()
local files, changes = app.page.model, 0
local originalChanged = app.review.services.basketChanged
app.review.services.basketChanged = function() changes=changes+1; originalChanged() end
local total = #files.visible
local button = app.page.refs.decisionAction
t.assertEqual(button.title,'Mark ' .. Model.plural(total,'File'),'initial bulk action uses eligible visible count')
files:markFiles()
t.assertEqual(changes,1,'bulk staging publishes once for every file together')
button = app.page.refs.decisionAction
t.assertEqual(button.title,'Review Marked Items…','staged files offer review immediately')
t.expect(button.enabled,'review remains available')
local item = app.review.basket:rows()[1]
app.review:toggle(item)
t.assertEqual(app.page.refs.decisionAction.title,'Mark 1 File','individual unmark refreshes count')
app.query='Old macOS Installer'; app:updateRows()
t.assertEqual(#files.visible,1,'search narrows displayed files')
local row = files.visible[1]
if app.review:isMarked(row.path) then app.review:toggle(row) end
files:markFiles()
t.assertEqual(app.page.refs.decisionAction.title,'Review Marked Items…','filtered staging stays current')
local reviewed = 0
app.actions.handlers.review = function() reviewed=reviewed+1 end
ns._invokeAction(app.page.refs.decisionAction)
t.assertEqual(reviewed,1,'review action routes to existing review sheet')
app:show('applications'); app.review.basket:clear(); app:basketChanged()
app:show('files')
t.expect(app.page.refs.decisionAction.title:find('Mark ',1,true),'cross-page clearing is reflected on return')
files.filterIndex = require('apps.diskmap.models.Files').filterIndex('Installers & archives')
app.query=''; app:updateRows(); bridge._flushLayout()
local refs = app.page.refs
t.expect(refs.scopeNote.superview ~= refs.pageContent,'accounting is disclosed separately')
local function yFromTop(view)
	local root, y, height = refs.pageContent, 0, view.frame.size.height
	while view and view ~= root do y=y+view.frame.origin.y; view=view.superview end
	return root.frame.size.height-y-height
end
t.expect(yFromTop(refs.filesPanel) < 260,'first file rows arrive before accounting at minimum size')
t.expect(yFromTop(refs.scanDetails) > yFromTop(refs.filesPanel),'scan statistics follow actual files')

app:show('applications')
app.page.actions.markHigh()
t.assertEqual(app.page.refs.decisionAction.title,'Review Marked Items…','marked likely leftovers route to review')
app.review.basket:clear(); app:basketChanged()
local leftovers = app.page.model.visibleLeftovers
local high
for _, value in ipairs(leftovers) do if value.tier=='high' then high=value;break end end
app.review:toggle({path=high.path,name=high.name,bytes=high.bytes,source='Leftovers',leftover=true,consequence='Leftover'})
t.assertEqual(app.page.refs.decisionAction.title,'Mark 1 Likely Leftover','leftover action counts only remaining folders')

app:show('worktrees')
local worktrees = app.graph:get('worktrees')
local page = app.page
page.refs.reviewList:selectRow(0)
local selected = worktrees.selected
selected.name = string.rep('long-project-name-',12)
selected.branch = string.rep('feature/branch/',12)
selected.reasons = {string.rep('Complete local evidence that must stay accessible. ',60)}
app:updateRows(); bridge._flushLayout()
t.expect(page.refs.selectionEvidence.frame.size.height <= 144,'long evidence scrolls inside a bounded inspector')
t.expect(page.refs.openOwner.frame.size.width > 0 and page.refs.openOwner.enabled,'owner action remains usable with long evidence')
t.expect(page.refs.page.frame.size.height > 200,'long evidence leaves usable inventory space (' .. page.refs.page.frame.size.height .. ' page, ' .. page.refs.selectionSection.frame.size.height .. ' selection, ' .. page.refs.selectionEvidence.frame.size.height .. ' evidence)' )
t.assertEqual(Worktrees.roleNames.recent,'Recent','compact recent label fits')
t.assertEqual(Worktrees.roleNames.active,'In use','confirmed activity stays distinct')
service.openOwner = function() return false,'Owner app unavailable' end
page.actions.openOwner()
t.assertEqual(page.refs.status.text,'Owner app unavailable','owner launch failure is visible beside selection')
window:close()
os.exit(t.summary() and 0 or 1)
