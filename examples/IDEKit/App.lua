local App = require("App")
local Recent = require("examples.IDEKit.state.Recent")
local Workspace = require("examples.IDEKit.Workspace")
local Welcome = require("examples.IDEKit.Welcome")

local app = App.new {
	name = "ide",
	recentKey = "ide",
	recentLimit = 12,
	openFolderPrompt = "Open Folder",
	openFilePrompt = "Open File",
	pluginDir = "examples/IDEKit/plugins",
	recent = Recent.new {
		key = "ide",
		limit = 12,
	},
	openFolder = function(self, folder)
		return Workspace.open(folder, self)
	end,
	openFile = function(self, path)
		return Workspace.openFile(path, self)
	end,
	welcome = function(self)
		return Welcome {
			title = "lua-objc IDE",
			recentFolders = self.recent:folders(),
			recentFiles = self.recent:files(),
			onOpenFolder = function()
				local folder = self:pickFolder()
				if folder then
					self:openFolder(folder)
				end
			end,
			onOpenFile = function()
				local path = self:pickFile()
				if path then
					self:openFile(path)
				end
			end,
			onOpenRecent = function(item)
				if item and item.path then
					if item.kind == "file" then
						self:openFile(item.path)
					else
						self:openFolder(item.path)
					end
				end
			end,
			onOpenExample = function()
				self:openFolder("examples")
			end,
		}
	end,
}

return app
