local t = require("TestKit")
local child = assert(io.tmpfile())
local controller = {}
package.loaded.UIKitNative = {
	_hostingController = function(content) assert(content==child);return controller end,
	Size = function(width,height) return {width=width,height=height} end,
}
local UIKit = assert(loadfile("lua/embedded/UIKit.lua"))()
t.assertEqual(UIKit.Sheet({child,width=560,height=640}),controller,"Sheet preserves its native hosting controller")
t.assertEqual(controller.preferredContentSize.width,560,"XML sheet width reaches native preferred sizing")
t.assertEqual(controller.preferredContentSize.height,640,"XML sheet height reaches native preferred sizing")
UIKit.Sheet({child,width=480,height=360})
t.assertEqual(controller.preferredContentSize.height,360,"a smaller sheet gets its own preferred height")
controller.preferredContentSize=nil
UIKit.Sheet({child})
t.assertEqual(controller.preferredContentSize,nil,"unspecified dimensions retain system sizing")
t.expect(not pcall(UIKit.Sheet,{child,child}),"sheets still require exactly one content child")
child:close()
os.exit(t.summary() and 0 or 1)
