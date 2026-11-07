local t = require("TestKit")
local presented, dismissed, updated, current = 0, 0, 0, nil
local options, shellData, shellPath
package.loaded["ui.xml"] = {renderFile=function(path, data) shellPath=path;shellData=data;return {}, {content={}} end}
package.loaded["ui.template"] = {new=function(_, path)
	current = {path=path,update=function(self,data) updated=updated+1;self.data=data end}
	return current
end}
local Sheets = require("apps.studio.controllers.SheetController")
local sheets = Sheets.new({
	presentSheet=function(builder, config) options=config;presented=presented+1;builder() end,
	dismiss=function() dismissed=dismissed+1;current.closed=true end,
})
sheets:present("Catalog",{title="Templates"})
t.assertEqual(options.presentationStyle,"pageSheet","catalogs retain their existing page presentation")
t.assertEqual(options.detents[1],"large","catalogs retain the large detent")
local shell = sheets.template
sheets:present("Project",{title="New Project"})
t.assertEqual(presented,1,"choosing a template reuses the existing native sheet")
t.assertEqual(dismissed,0,"content changes do not dismiss the presenting controller")
t.assertEqual(sheets.template,shell,"the retained sheet owns the next screen")
t.assertEqual(shell.path,"apps/studio/views/sheets/Project.etlua","the new etlua view is rendered")
t.assertEqual(shell.data.title,"New Project","the replacement receives its own data")
sheets:update({message="Invalid name"})
t.assertEqual(updated,3,"validation updates the same sheet")
sheets:close();sheets:close()
t.assertEqual(dismissed,1,"closing a sheet twice dismisses only once")
sheets:present("Settings",{title="Settings"})
t.assertEqual(presented,2,"a later sheet starts a fresh native presentation")
t.expect(sheets.template~=shell,"disposed templates are not reused")
t.assertEqual(options.presentationStyle,"formSheet","Settings uses a centered native popup")
t.assertEqual(options.detents,nil,"Settings does not request a full-height detent")
t.assertEqual(options.dragIndicator,false,"the compact popup has no expansion handle")
t.assertEqual(shellData.widthResource,nil,"UIKit owns the default Settings popup width")
t.assertEqual(shellData.heightResource,nil,"UIKit owns the default Settings popup height")
t.expect(shellPath:find("SettingsShell.etlua",1,true),"Settings uses the native navigation shell")
os.exit(t.summary() and 0 or 1)
