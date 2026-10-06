-- The general pasteboard, so the page can copy a translation without
-- touching the platform.
local Clipboard = {}

function Clipboard.copy(text)
	require("ns").copyToClipboard(text)
end

return Clipboard
