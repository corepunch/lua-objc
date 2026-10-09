local O = require("tests.support.diskmap_operations")
_G.__headless = true
local t=require('TestKit')
local ns=require('AppKit')
local bridge=require('AppKitNative')
local Marks = require("apps.diskmap.models.Marks")
local Files=require('apps.diskmap.models.Files')
local Root=require('apps.diskmap.Controller')
local Mock=require('apps.diskmap.services.Mock')
local home='/Users/review'
require("apps.diskmap.Store").new(home)
local basket = Marks
local folder=home..'/Downloads/review-folder'
local child=folder..'/large.zip'
local sibling=home..'/Downloads/review-folder-sibling/file.zip'
local function item(path) return {path=path,name=path:match('([^/]+)$'),bytes=90000000} end
for _, invalid in ipairs({false,42,{},'relative'}) do
	t.expect(basket:covering(invalid)==nil,'malformed coverage does not throw')
	local ok=basket:add({path=invalid,name='Malformed item'})
	t.expect(not ok,'invalid root or relative staging is refused')
end
t.expect(basket:covering(nil)==nil,'nil coverage is empty')
t.expect(basket:add(item(child)),'leaf can be staged')
t.expect(basket:add(item(folder)),'parent replaces its staged leaf')
t.assertEqual(basket:count(),1,'parent replacement never double counts')
local covering,exact=basket:covering(child)
t.assertEqual(covering.path,folder,'child resolves enclosing staged folder')
t.expect(not exact and not basket:contains(child),'included leaf is not an exact mark')
t.expect(not basket:remove(child),'leaf unmark never removes its enclosing folder')
t.assertEqual(basket:count(),1,'folder remains after refused child unmark')
local ok,reason=basket:add(item(child))
t.expect(not ok and reason:find('Included',1,true),'redundant child reports inclusion')
t.expect(basket:covering(sibling)==nil,'similarly named sibling stays independent')
t.expect(basket:add(item(sibling)),'sibling still stages independently')
t.expect(basket:remove(folder),'explicit parent unmark works')
t.expect(basket:covering(child)==nil,'parent removal removes coverage')
t.expect(basket:add(item(child)),'child becomes eligible after parent unmark')
local service=Mock.new()
local app=Root.new(service)
local window=app:createWindow()
for _, value in ipairs({42, false, {}, 'relative'}) do
	local ok=app.env.basket:toggle({path=value,name='Malformed item'})
	t.expect(not ok,'malformed staged path is refused without throwing')
end
t.assertEqual(app.env.basket:markAll({false,42,{path=42},{path='/bad/../path'}}),0,'invalid bulk items never stage')
t.assertEqual(app.env.basket:count(),0,'refused staging leaves basket empty')
app.env.scan:start()
window.size=ns.Size(950,580);window:layout()
local liveFolder=app.env.model.home..'/Downloads/review-folder'
local liveChild=liveFolder..'/cleanup-fixture-nested-archive.zip'
table.insert(app.env.model.files.large,{path=liveChild,bytes=90000000,used=os.time()})
app.env.basket:toggle({path=liveFolder,name='Review folder',bytes=90000000,consequence='Moves this folder and every file inside it.'})
-- Large Files lists only the file inside the marked folder.
local fullLarge=app.env.model.files.large
app.env.model.files.large={fullLarge[#fullLarge]}
app:show('files');app:updateRows()
local page=app.page.request
local decision=app.page.refs
t.assertEqual(decision.decisionAction.title,'Review Marked Items…','covered visible file routes to review')
t.expect(decision.decisionDetail.text:find('included through a marked folder',1,true),'bulk feedback explains folder coverage')
t.assertEqual(page:markFiles(),0,'bulk skips covered leaves')
t.assertEqual(app.env.basket:count(),1,'bulk keeps enclosing folder intact')
local menu=app.env.rowActions:mark(item(liveChild))
t.expect(menu.title:find('Included through',1,true),'covered row has explicit review menu')
menu.action()
t.assertEqual(app.env:page("basket").selected.path,liveFolder,'covered row opens enclosing staged item')
t.assertEqual(app.env:page("basket").refs.selectedPath.text,liveFolder,'review displays full enclosing path')
t.expect(app.env:page("basket").refs.consequence.text:find('every file',1,true),'review displays concrete consequence')
t.expect(O(app, "remove").enabled,'enclosing selection can be explicitly unmarked')
app:show('files')
local source={path=liveChild,name='Large file',subtitle='Original folder',icon='doc',bytes=90000000}
local presented=app.env.rowActions:annotate({source})[1]
t.expect(presented.subtitle:find('Included through',1,true),'shared rows explain inclusion')
t.assertEqual(source.subtitle,'Original folder','row feedback does not mutate inventory data')
app.env.basket:toggle(item(liveFolder))
presented=app.env.rowActions:annotate({source})[1]
t.assertEqual(presented.subtitle,'Original folder','unmark removes coverage feedback')
t.assertEqual(app.page.refs.decisionAction.title,'Mark 1 File','parent unmark makes leaf eligible again')
app.env.basket:toggle({path=liveChild,name='Installer',bytes=90000000,consequence='Check that installation is complete before removing this installer.'})
t.assertEqual(app.env.rowActions:mark(item(liveChild)).title,'Remove Review Flag','exact mark keeps its own unmark semantics')
app:openReview()
t.assertEqual(app.env:page("basket").selected.path,liveChild,'opening review selects first pending item')
t.expect(app.env:page("basket").refs.consequence.text:find('installation is complete',1,true),'default selection exposes item-specific consequence')
t.assertEqual(app.env:page("basket").refs.selectedPath.text,liveChild,'full selected path is retained')
t.expect(app.env:page("basket").refs.revalidation.text:find('checked just before',1,true),'generic revalidation remains visible')
local long=string.rep('A concrete consequence must stay readable before removing this file. ',20)
Marks:find(liveChild).consequence=long
app:updateRows();bridge._flushLayout()
t.assertEqual(app.env:page("basket").selected.path,liveChild,'refresh preserves a still-present selection')
t.assertEqual(app.env:page("basket").refs.consequence.text,long,'long consequence remains complete')
t.expect(app.env:page("basket").refs.selectedDetails.size.height >=120 and app.env:page("basket").refs.selectedDetails.size.height<=144,'long consequence has a usable bounded viewport')
app.page.actions.remove()
t.assertEqual(app.env.basket:count(),0,'unmark selected only changes basket')
t.expect(app.env:page("basket").selected==nil and app.env:page("basket").refs.selectedDetails.hidden,'unmark clears missing inspector')
t.expect(not O(app, "trash").enabled,'empty basket disables move')
app.env:page("basket").done={[liveChild]='Moved to Trash'};app:updateRows();app.env:page("basket").refs.items:selectRow(0)
t.assertEqual(app.env:page("basket").refs.selectedResult.text,'Moved to Trash','completed result has readable detail')
t.expect(not O(app, "remove").enabled,'result row cannot be unmarked again')
app.env.basket:toggle({path=liveChild,name='Installer',bytes=90000000})
app:updateRows();app.env:page("basket").refs.items:selectRow(0)
app.page.actions.clear()
t.expect(app.env:page("basket").refs.selectedDetails.hidden and not O(app, "trash").enabled,'clear all hides details and disables removal')
app:show("overview")
app.env.model.files.large=fullLarge
local savedFiles=app.env.model.files
app.env.model.files=nil;app.env.model.scan={running=true}
app:show('files')
app:updateRows()
t.expect(app.page.refs.waiting~=nil,'while the scan runs Large Files says it is not measured yet')
t.expect(app.page.refs.decisionAction==nil and app.page.refs.files==nil,'a running scan makes no marking offer and lists no partial rows')
app:show('kinds')
t.expect(app.page.refs.waiting~=nil and app.page.refs.kinds==nil and app.page.refs.extensions==nil,'File Types waits for the scan too, with no table')
app.env.model.files={large={},old={},extensions={},oldBytes=0,oldCount=0};app.env.model.scan={running=false}
app:show('files')
app:updateRows()
t.expect(not app.page.refs.filesNone.hidden and app.page.refs.filesPanel.hidden,'completed empty files replace inventory scaffolding')
t.assertEqual(app.page.refs.decisionAction.title,'Open Clean Up','empty files route to another cleanup opportunity')
app:show('kinds')
t.expect(app.page.refs.waiting==nil and app.page.refs.computing==nil,'completed empty types never claim loading')
t.expect(app.page.refs.kinds==nil and app.page.refs.extensions==nil and app.page.refs.breakdownChart==nil,'empty types suppress empty tables and chart')
t.assertEqual(app.page.refs.decisionAction.title,'Open Clean Up','empty types give another cleanup route')
app.env.model.files={large={},old={},extensions={{extension='txt',bytes=100000,count=2}},oldBytes=0,oldCount=0}
app:show('files');page=app.page.request;app:updateRows()
t.expect(not app.page.refs.filesNone.hidden and app.page.refs.filesEmpty.hidden,'small files are not presented as a filter mismatch')
t.expect(app.page.refs.decisionDetail.text:find('over 50',1,true),'no large-file result explains the threshold')
app:show('kinds')
t.expect(app.page.refs.kinds~=nil,'under-threshold files still contribute to types')
app.env.model.scan={failure='Scan could not read its roots'}
app:show('files');page=app.page.request;app:updateRows()
t.expect(app.page.refs.decisionDetail.text:find('could not read',1,true),'scan failure is explicit')
t.assertEqual(app.page.refs.decisionAction.title,'Refresh Scan','unavailable files offer refresh')
app:show('kinds')
t.assertEqual(app.page.refs.decisionAction.title,'Refresh Scan','failed types offer refresh')
app.env.model.files=nil;app.env.model.scan={running=false}
t.assertEqual(Files.state(app.env.model),'unavailable','no results after scan is unavailable, never empty')
app.env.model.files=savedFiles;app.env.model.scan={running=false}
local project=app.env:page('projects')
local group={path=liveFolder,name='Review project',artifacts={{path=liveFolder..'/node_modules',name='Node modules',bytes=9000,size='9 KB'}}}
app.env.basket:toggle(item(liveFolder))
local covered=project:menu(group)
t.expect(covered[1].title:find('Included through',1,true),'covered project offers enclosing review and no mark of its own')
for _, entry in ipairs(covered) do t.expect(not (entry.title or ''):find('Build Data',1,true),'a covered project cannot unmark its enclosing sources folder') end
app.env.basket:toggle(item(liveFolder));project:menu(group)[1].action()
t.assertEqual(project:menu(group)[1].title,'Unmark Build Data','direct artifact marks keep their own unmark action')
Marks:clear();app:basketChanged()
app:show('worktrees');local worktrees=app.page
worktrees.refs.reviewList:selectRow(0)
local selected=app.env:page("worktrees").selected
selected.reasons={string.rep('Review unpublished work with the owning session before deleting. ',25)}
app:updateRows();bridge._flushLayout()
t.expect(worktrees.refs.selectedSummary.size.height > 144, 'long evidence expands naturally in the shared page scroller')
t.expect(worktrees.refs.selectionSection.superview == worktrees.refs.pageContent, 'selected evidence is page content')
t.expect(O(app, "openOwner").enabled,'action remains accessible')
app:show('files');page=app.page.request;page:focus({kind='installers',filter='Installers & archives'});app:updateRows();bridge._flushLayout()
t.expect(not app.page.refs.clearKind.hidden,'real kind focus reveals Show All Kinds')
local parent=app.page.refs.clearKind.superview
local button=app.page.refs.clearKind.frame
t.expect(parent.size.height>=button.size.height,'visible kind action fits its controls row')
t.expect(button.origin.y>=0 and button.origin.y+button.size.height<=parent.size.height,'visible kind action does not overlap filter')
app.page.actions.clearKind();bridge._flushLayout()
t.expect(app.page.refs.clearKind.hidden,'clearing kind restores hidden route')
window:close()
os.exit(t.summary() and 0 or 1)
