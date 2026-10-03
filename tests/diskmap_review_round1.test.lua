_G.__headless = true
local Marks = require("apps.diskmap.models.Marks")
local t = require('TestKit')
local ns = require('AppKit')
local bridge = require('AppKitNative')
local Mock = require('apps.diskmap.services.Mock')
local Root = require('apps.diskmap.Controller')
local Files = require('apps.diskmap.models.Files')
local Navigation = require('apps.diskmap.controllers.NavigationController')
local service = Mock.new()
local app = Root.new(service)
local window = app:createWindow()
app.env.scan:start()
window.size = ns.Size(950, 580); window:layout()

-- Real root navigation disposes and remounts this same page instance. Keep
-- both family selections and the chosen runtime through that lifecycle.
app:show('simulators')
local page = app.env:page("simulators")
local choices = {}
for _, family in ipairs({'iPhone','iPad'}) do
	local plan = page:plan()
	for index, row in ipairs(plan.candidates[family]) do
		if row.id ~= plan.keep[family] then
			-- The Picker lists "Choose…" first only when the family needs a choice.
			page:chooseKeep(family, index - 1 + (plan.needsChoice[family] and 1 or 0)); choices[family] = row.id; break
		end
	end
	t.expect(choices[family] ~= nil, 'the fixture has an alternative ' .. family)
end
local runtime = page:plan().runtime
app:show('cleanup'); app:show('simulators')
t.assertEqual(page:plan().runtime, runtime, 'navigation preserves selected runtime')
for family, id in pairs(choices) do
	t.assertEqual(page:plan().keep[family], id, 'navigation preserves chosen ' .. family)
	for _, row in ipairs(page:plan().removal) do t.expect(row.id ~= id, 'chosen ' .. family .. ' never enters removal plan') end
end

-- The heading and explanation have their own row, above filters/actions;
-- verify actual native geometry, rather than matching template strings.
app:show('projects'); bridge._flushLayout()
local refs = app.page.refs
t.expect(refs.projectRoots.frame.size.width > 400, 'project explanation keeps readable width at 950 points')
t.expect(not refs.projectRoots.text:find('Searching', 1, true), 'completed discovery does not say Searching')
t.assertEqual(refs.markStale.title, 'Mark Old Build Data', 'bulk action names the generated data')
t.expect(refs.filter.superview ~= refs.projectRoots.superview, 'filters do not compress the heading')
for _, width in ipairs({950, 1100, 1400}) do
	window.size = ns.Size(width, 580); window:layout(); bridge._flushLayout()
	local controls = refs.filter.superview
	t.assertEqual(refs.markStale.superview, controls, 'project marking and filtering share a row at ' .. width)
	t.assertEqual(refs.markStale.frame.origin.x, 0, 'project marking starts at the leading edge at ' .. width)
	t.assertEqual(refs.filter.frame.origin.x + refs.filter.frame.size.width, controls.frame.size.width,
		'project filters end at the trailing edge at ' .. width)
	t.expect(refs.markStale.frame.origin.x + refs.markStale.frame.size.width <= refs.filter.frame.origin.x,
		'project marking and filters do not overlap at ' .. width)
	t.expect(math.abs(refs.markStale.frame.origin.y + refs.markStale.frame.size.height / 2
		- refs.filter.frame.origin.y - refs.filter.frame.size.height / 2) < 0.01,
		'project marking and filters share a center line at ' .. width)
end
window.size = ns.Size(950, 580); window:layout()

-- Selection evidence is a fixed sibling of the scrolling list, immediately
-- accessible even when the list has many worktrees.
app:show('worktrees'); refs = app.page.refs
t.expect(refs.selectionSection.hidden, 'empty worktree inspector uses no space')
refs.reviewList:selectRow(0); bridge._flushLayout(); refs = app.page.refs
t.expect(not refs.selectionSection.hidden, 'selection exposes evidence')
t.expect(refs.selectionSection.superview == refs.page.superview, 'evidence stays outside scrolling inventory')
t.expect(refs.selectedDetail.text:find(app.env:page("worktrees").selected.path, 1, true), 'selection exposes complete path')
t.expect(refs.openOwner.enabled, 'managed checkout exposes its owner action')
local widths = bridge._tableColumnWidths(refs.reviewList)
t.expect(widths[1].width > widths[2].width and widths[1].width > widths[3].width, 'name/branch gets more space than repeated status/date')

-- Installer arrival leads with the actual filtered subset, with staging
-- only; no confirmation or deletion is triggered by marking.
app:show('kinds'); app.page.actions.showInstallers()
local rows = Files:rows('Installers & archives')
local bytes = 0
for _, row in ipairs(rows) do bytes = bytes + row.bytes end
local lead = app.page.refs
t.assertEqual(lead.decisionAmount.text, require("apps.diskmap.helpers.Format").size(bytes), 'file decision totals only the visible subset')
t.assertEqual(lead.decisionCaption.text, 'to review', 'documents are review candidates')
local before = app.env.basket:count()
ns._invokeAction(lead.decisionAction)
t.expect(app.env.basket:count() > before, 'marking stages visible installers')
for _, row in ipairs(rows) do t.expect(app.env.basket:isMarked(row.path), 'each installer is staged') end
Marks:clear(); app:basketChanged()
t.expect(app.collector.collectorArea.hidden, 'empty collector collapses')
local deferred, originalAsync, originalSleep = {}, ns.async, ns.sleep
ns.async = function(fn) table.insert(deferred, fn) end
ns.sleep = function() end
app.collectorController:drag('page', true)
t.expect(not app.collector.collectorArea.hidden, 'file drag reveals staging')
app.collectorController:drag('collector', true); app.collectorController:drag('page', false)
for _, fn in ipairs(deferred) do fn() end

deferred = {}
t.expect(not app.collector.collectorArea.hidden, 'moving from parent to collector retains staging')
app.collectorController:drag('collector', false)
for _, fn in ipairs(deferred) do fn() end

deferred = {}
t.expect(app.collector.collectorArea.hidden, 'drag exit collapses an empty collector')
app.collectorController:drag('page', true); app.collectorController:drag('page', false)
app.collectorController:drag('collector', true)
for _, fn in ipairs(deferred) do fn() end

deferred = {}
t.expect(not app.collector.collectorArea.hidden, 'new drag supersedes queued exit')
app.collectorController:drag('collector', false)
for _, fn in ipairs(deferred) do fn() end
ns.async, ns.sleep = originalAsync, originalSleep
t.expect(app.collector.collectorArea.hidden, 'no drag and no staged items collapses collector')

app:show('applications')
local applicationLead = app.page.refs
t.expect(applicationLead.decisionAction.title:find('Likely Leftover', 1, true), 'app cleanup action uses concrete language')
for _, row in ipairs(Navigation.destinations) do
	if row.id == 'developer' then t.assertEqual(row.name, 'Dev tools', 'workflow label distinguishes owner category') end
end
app:show('developer')
t.expect(app.page.refs.scopeNote.text:find('different set', 1, true), 'workflow explains its distinct accounting scope')
window:close()

os.exit(t.summary() and 0 or 1)
