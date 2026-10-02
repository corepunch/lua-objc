_G.__headless = true
local t=require('TestKit')
local ns=require('AppKit')
local bridge=require('AppKitNative')
local Basket=require('apps.diskmap.models.Basket')
local Files=require('apps.diskmap.models.Files')
local Root=require('apps.diskmap.Controller')
local Mock=require('apps.diskmap.services.Mock')
local home='/Users/review'
local basket=Basket.new(home)
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
	local ok=app.review:toggle({path=value,name='Malformed item'})
	t.expect(not ok,'malformed staged path is refused without throwing')
end
t.assertEqual(app.review:markAll({false,42,{path=42},{path='/'}}),0,'invalid bulk items never stage')
t.assertEqual(app.review:count(),0,'refused staging leaves basket empty')
app.scan:start()
window.size=ns.Size(950,580);window:layout()
local liveFolder=app.model.home..'/Downloads/review-folder'
local liveChild=liveFolder..'/cleanup-fixture-nested-archive.zip'
table.insert(app.model.files.large,{path=liveChild,bytes=90000000,used=os.time()})
app.review:toggle({path=liveFolder,name='Review folder',bytes=90000000,consequence='Moves this folder and every file inside it.'})
app:show('files');app.session.query='cleanup-fixture-nested-archive.zip';app:updateRows()
local page=app.page
local decision=page.refs
t.assertEqual(decision.decisionAction.title,'Review Marked Items…','covered visible file routes to review')
t.expect(decision.decisionDetail.text:find('included through a marked folder',1,true),'bulk feedback explains folder coverage')
t.assertEqual(app:pageModel("files"):markFiles(),0,'bulk skips covered leaves')
t.assertEqual(app.review:count(),1,'bulk keeps enclosing folder intact')
local menu=app.actions:mark(item(liveChild))
t.expect(menu.title:find('Included through',1,true),'covered row has explicit review menu')
menu.action()
t.assertEqual(app.review.selected.path,liveFolder,'covered row opens enclosing staged item')
t.assertEqual(app.review.refs.selectedPath.text,liveFolder,'review displays full enclosing path')
t.expect(app.review.refs.consequence.text:find('every file',1,true),'review displays concrete consequence')
t.expect(app.review.refs.remove.enabled,'enclosing selection can be explicitly unmarked')
app.review:close()
local source={path=liveChild,name='Large file',subtitle='Original folder',icon='doc',bytes=90000000}
local presented=app.actions:annotate({source})[1]
t.expect(presented.subtitle:find('Included through',1,true),'shared rows explain inclusion')
t.assertEqual(source.subtitle,'Original folder','row feedback does not mutate inventory data')
app.review:toggle(item(liveFolder))
presented=app.actions:annotate({source})[1]
t.assertEqual(presented.subtitle,'Original folder','unmark removes coverage feedback')
t.assertEqual(page.refs.decisionAction.title,'Mark 1 File','parent unmark makes leaf eligible again')
app.review:toggle({path=liveChild,name='Installer',bytes=90000000,consequence='Check that installation is complete before removing this installer.'})
t.assertEqual(app.actions:mark(item(liveChild)).title,'Unmark','exact mark keeps its own unmark semantics')
app.review:open(window)
t.assertEqual(app.review.selected.path,liveChild,'opening review selects first pending item')
t.expect(app.review.refs.consequence.text:find('installation is complete',1,true),'default selection exposes item-specific consequence')
t.assertEqual(app.review.refs.selectedPath.text,liveChild,'full selected path is retained')
t.expect(app.review.refs.revalidation.text:find('checked just before',1,true),'generic revalidation remains visible')
local long=string.rep('A concrete consequence must stay readable before removing this file. ',20)
app.review.basket.items[liveChild].consequence=long
app.review:show();bridge._flushLayout()
t.assertEqual(app.review.selected.path,liveChild,'refresh preserves a still-present selection')
t.assertEqual(app.review.refs.consequence.text,long,'long consequence remains complete')
t.expect(app.review.refs.selectedDetails.size.height >=120 and app.review.refs.selectedDetails.size.height<=144,'long consequence has a usable bounded viewport')
ns._invokeAction(app.review.refs.remove)
t.assertEqual(app.review:count(),0,'unmark selected only changes basket')
t.expect(app.review.selected==nil and app.review.refs.selectedDetails.hidden,'unmark clears missing inspector')
t.expect(not app.review.refs.trash.enabled,'empty basket disables move')
app.review.done={[liveChild]='Moved to Trash'};app.review:show();app.review.refs.items:selectRow(0)
t.assertEqual(app.review.refs.selectedResult.text,'Moved to Trash','completed result has readable detail')
t.expect(not app.review.refs.remove.enabled,'result row cannot be unmarked again')
app.review:toggle({path=liveChild,name='Installer',bytes=90000000})
app.review:show();app.review.refs.items:selectRow(0)
ns._invokeAction(app.review.refs.clear)
t.expect(app.review.refs.selectedDetails.hidden and not app.review.refs.trash.enabled,'clear all hides details and disables removal')
app.review:close()
local savedFiles=app.model.files
app.model.files=nil;app.model.scan={running=true}
app:show('files');page=app.page
app.session.query='';app:updateRows()
t.assertEqual(page.refs.decisionAmount.text,'—','loading does not pretend zero bytes')
t.expect(page.refs.decisionAction.hidden,'loading makes no false-zero marking offer')
t.expect(not page.refs.filesPanel.hidden and page.refs.fileControls.hidden,'loading keeps native spinner surface and hides controls')
app:show('kinds')
t.assertEqual(app.page.refs.summary.text,'Scan in progress','kinds loading has a progress header')
t.expect(app.page.refs.kinds~=nil and app.page.refs.extensions==nil,'loading has one native table surface')
app.model.files={large={},old={},extensions={},oldBytes=0,oldCount=0};app.model.scan={running=false}
app:show('files');page=app.page
app.session.query='';app:updateRows()
t.expect(not page.refs.filesNone.hidden and page.refs.filesPanel.hidden,'completed empty files replace inventory scaffolding')
t.assertEqual(page.refs.decisionAction.title,'Open Clean Up','empty files route to another cleanup opportunity')
app:show('kinds')
t.expect(not app.page.refs.summary.text:find('Measuring',1,true),'completed empty types never claim loading')
t.expect(app.page.refs.kinds==nil and app.page.refs.extensions==nil and app.page.refs.kindsChart==nil,'empty types suppress empty tables and chart')
t.assertEqual(app.page.refs.decisionAction.title,'Open Clean Up','empty types give another cleanup route')
app.model.files={large={},old={},extensions={{extension='txt',bytes=100000,count=2}},oldBytes=0,oldCount=0}
app:show('files');page=app.page;app.session.query='';app:updateRows()
t.expect(not page.refs.filesNone.hidden and page.refs.filesEmpty.hidden,'small files are not presented as a filter mismatch')
t.expect(page.refs.decisionDetail.text:find('over 50',1,true),'no large-file result explains the threshold')
app:show('kinds')
t.expect(app.page.refs.kinds~=nil,'under-threshold files still contribute to types')
app.model.scan={failure='Scan could not read its roots'}
app:show('files');page=app.page;app.session.query='';app:updateRows()
t.expect(page.refs.decisionDetail.text:find('could not read',1,true),'scan failure is explicit')
t.assertEqual(page.refs.decisionAction.title,'Refresh Scan','unavailable files offer refresh')
app:show('kinds')
t.assertEqual(app.page.refs.decisionAction.title,'Refresh Scan','failed types offer refresh')
app.model.files=nil;app.model.scan={running=false}
t.assertEqual(Files.state(app.model),'unavailable','no results after scan is unavailable, never empty')
app.model.files=savedFiles;app.model.scan={running=false}
app:show('files');page=app.page;app.session.query='no-match-for-review';app:updateRows()
t.assertEqual(page.refs.decisionAction.title,'Clear Search','no-match files provide a useful next step')
app:show('kinds');app.session.query='no-match-for-review';app:updateRows()
t.assertEqual(app.page.refs.decisionAction.title,'Clear Search','no-match file types offer clear search')
t.expect(app.page.refs.kinds==nil and app.page.refs.extensions==nil,'no-match types suppress inventory scaffolding')
local Projects=require('apps.diskmap.controllers.ProjectsController')
local project=Projects.new({model=app.model,service=service,actions=app.actions,rescan=function() end})
local group={path=liveFolder,name='Review project',artifacts={{path=liveFolder..'/node_modules',name='Node modules',bytes=9000,size='9 KB'}}}
app.review:toggle(item(liveFolder))
t.expect(project:included(group) and not project:isMarked(group),'project distinguishes covered artifacts from exact marks')
t.expect(project:menu(group)[1].title:find('Included through',1,true),'covered project offers enclosing review')
project:mark(group)
t.assertEqual(app.review:count(),1,'project bulk never tries to unmark enclosing sources folder')
app.review:toggle(item(liveFolder));project:mark(group)
t.assertEqual(project:menu(group)[1].title,'Unmark Build Data','direct artifact marks keep their own unmark action')
app.review.basket:clear();app:basketChanged()
app.session.query='';app:show('worktrees');local worktrees=app.worktrees
worktrees.refs.reviewList:selectRow(0)
local selected=worktrees.selected
selected.reasons={string.rep('Review unpublished work with the owning session before deleting. ',25)}
worktrees:buttons();bridge._flushLayout()
t.assertEqual(worktrees.refs.selectionEvidence.size.height,144,'actual long worktree evidence fills bounded viewport')
t.expect(worktrees.refs.page.size.height>200,'bounded evidence leaves usable inventory')
local document=worktrees.refs.selectedSummary.superview
local visibleTop=document.size.height-worktrees.refs.selectedSummary.frame.origin.y-worktrees.refs.selectedSummary.size.height
t.expect(visibleTop<worktrees.refs.selectionEvidence.contentView.bounds.size.height,'selected evidence starts within visible viewport')
t.expect(worktrees.refs.openOwner.enabled and worktrees.refs.openOwner.size.height>=24,'action remains accessible')
app:show('files');page=app.page;app:pageModel("files"):focus('installers');app.session.query='';app:updateRows();bridge._flushLayout()
t.expect(not page.refs.clearKind.hidden,'real kind focus reveals Show All Kinds')
local parent=page.refs.clearKind.superview
local button=page.refs.clearKind.frame
t.expect(parent.size.height>=button.size.height,'visible kind action fits its controls row')
t.expect(button.origin.y>=0 and button.origin.y+button.size.height<=parent.size.height,'visible kind action does not overlap filter')
app:pageModel('files'):clearKind();app:updateRows();bridge._flushLayout()
t.expect(page.refs.clearKind.hidden,'clearing kind restores hidden route')
window:close()
os.exit(t.summary() and 0 or 1)
