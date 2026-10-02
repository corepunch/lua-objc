local Model = require("data.model")
local Sdks = require("apps.diskmap.models.Sdks")

-- The SDK sheet's data: the SDKs of one installation, the search text and the
-- line below the list. The sheet's view binds to it by name (schemas/
-- SdkList.xml); the controller only starts the discovery and measuring.
local SdkList = Model.define({id = "sdks", schema = "SdkList"})

function SdkList.new()
	return setmetatable({all = {}, query = "", measuring = false, discovered = false}, SdkList)
end

function SdkList:setRows(rows)
	self.all, self.discovered = rows, true
end

function SdkList:setQuery(value)
	self.query = value or ""
end

function SdkList:rows()
	return Sdks.filter(self.all, self.query)
end

function SdkList:status()
	if not self.discovered then return "Reading SDK folders…" end
	if self.measuring then return "Measuring SDKs…" end
	local count = #self:rows()
	return count == 0 and "No matching SDKs." or (count .. (count == 1 and " SDK" or " SDKs"))
end

return SdkList
