local Format = require("apps.diskmap.helpers.Format")
local Outcome = {}

-- Results of a cleanup are reported the same way wherever it ran: what was
-- done, what was skipped and why, and the free space measured afterwards.

-- Free bytes on the disk holding `home`, or nil when the service cannot say.
function Outcome.free(service, home)
	local disk = service.diskSpace(home)
	return type(disk) == "table" and disk.freeKb and disk.freeKb * 1024 or nil
end

-- "Free space 12.0 GB → 14.1 GB (+2.1 GB)", or a note when it was not measured.
function Outcome.freeText(before, after, immediate)
	if not (before and after) then return "Free space could not be measured." end
	local change = after - before
	local text = "Free space " .. Format.size(before) .. " → " .. Format.size(after)
	if change > 0 then text = text .. " (+" .. Format.size(change) .. ")" end
	if change <= 0 and immediate then text = text .. ". macOS may report space released after a short delay" end
	return text
end

return Outcome
