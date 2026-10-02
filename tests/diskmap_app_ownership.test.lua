_G.__headless = true
local t=require('TestKit')
local Model=require('apps.diskmap.Model')
local Applications=require('apps.diskmap.models.Applications')
local Leftovers=require('apps.diskmap.models.Leftovers')
local home='/Users/review'
local model=Model.new(home)
model.resources:add('applications',{id='renamed-app',name='ChatGPT.app',path='/Applications/ChatGPT.app'})
model.measurements['renamed-app']={status='complete',bytes=100000000}
model.breakdowns.support={
	{name='Codex',directory=true,kb=100000},
	{name='ChatGPT',directory=true,kb=50000},
	{name='com.openai.codex.helper',directory=true,kb=20000},
	{name='Codex old',directory=true,kb=60000},
	{name='UnrelatedCodex',directory=true,kb=70000},
}
model.breakdowns['app-containers']={{name='com.openai.codex',directory=true,kb=45000}}
local info={['/Applications/ChatGPT.app']={bundleId='com.openai.codex',displayName='ChatGPT'}}
local rows=Applications.rows(model,info,'All')
local app
for _, row in ipairs(rows) do if row.resourceId=='renamed-app' then app=row end end
t.assertEqual(app.name,'ChatGPT','installed app keeps its actual Finder name')
t.assertEqual(app.bundleId,'com.openai.codex','ownership uses canonical bundle identity')
t.assertEqual(app.dataBytes,(100000+50000+20000+45000)*1024,'renamed app includes its exact product folder and identifier data once')
t.assertEqual(app.bytes,100000000+app.dataBytes,'app and data totals include canonical storage ownership')
t.assertEqual(#app.folders,4,'unrelated similar folders are not claimed')
local unclaimed={}
for _, row in ipairs(Applications.leftovers(model,{'com.openai.codex'})) do unclaimed[row.name]=row end
t.expect(unclaimed.Codex==nil,'installed renamed bundle claims Codex support data')
t.expect(unclaimed['Codex old']~=nil and unclaimed.UnrelatedCodex~=nil,'similar folder names remain review candidates')
t.assertEqual(Leftovers.classify('Codex',true,Leftovers.index({{bundleId='com.openai.chat'}})),'low','a different OpenAI bundle does not claim Codex')
t.assertEqual(Leftovers.classify('Codex',true,Leftovers.index({{bundleId='com.example.codex'}})),'low','arbitrary bundle suffixes do not claim product storage')
t.assertEqual(Leftovers.classify('Codex',true,Leftovers.index({{bundleId='com.openai.codex'}})),nil,'installed identity claims storage even before filename metadata arrives')
t.assertEqual(Leftovers.classify('Codex',true,Leftovers.index({})),'low','removed bundle makes name-only data uncertain again')
model.measurements['renamed-app']={status='complete',bytes=0}
t.assertEqual(#Applications.data(model,'com.openai.chat','ChatGPT'),1,'unrelated identity receives only its explicitly matching name')
local decision=Applications.decision({leftovers=2,leftoversHigh=0,leftoversHighBytes=0,leftoverBytes=100000000},0,0)
t.expect(decision.title:find('possible leftover',1,true),'uncertain headline labels possibilities')
t.expect(not decision.title:find('no longer installed',1,true),'headline does not assert app removal')
t.expect(decision.detail:find('does not prove',1,true),'name-only evidence is explained honestly')
os.exit(t.summary() and 0 or 1)
