-- What the page sees as `self.app`: the offline engine (its dictionaries
-- load on the first keystroke) and the pasteboard.
local Translator = require("apps.translator.services.Translator")
local Clipboard = require("apps.translator.services.Clipboard")

return function()
	return { translator = Translator.new(), clipboard = Clipboard }
end
