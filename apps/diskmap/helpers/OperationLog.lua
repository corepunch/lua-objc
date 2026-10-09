local Format = require("apps.diskmap.helpers.Format")
local OperationLog = {}

-- One line per action in ~/Library/Logs/Diskmap/operations.log:
-- ISO time, action, result, bytes and target, tab separated. Tabs and
-- newlines inside fields are replaced so one action is always one line.
local function clean(value)
	return (tostring(value or ""):gsub("[\t\r\n]", " "))
end

function OperationLog.format(entry, time)
	return table.concat({os.date("!%Y-%m-%dT%H:%M:%SZ", time or os.time()), clean(entry.action),
		entry.ok and "ok" or "failed", tostring(math.floor(tonumber(entry.bytes) or 0)), clean(entry.target),
		clean(entry.detail)}, "\t")
end

function OperationLog.parse(line)
	local time, action, result, bytes, target, detail = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
	if not time then return nil end
	return {time = time, action = action, ok = result == "ok", bytes = tonumber(bytes) or 0, target = target, detail = detail}
end

-- Rows for the History page, newest first.
function OperationLog.rows(lines)
	local rows = {}
	for _, line in ipairs(lines or {}) do
		local entry = OperationLog.parse(line)
		if entry then
			table.insert(rows, {id = #rows + 1, name = entry.action, subtitle = entry.target,
				date = entry.time:gsub("T", " "):gsub("Z$", " UTC"), result = entry.ok and "Done" or ("Failed" .. (entry.detail ~= "" and (": " .. entry.detail) or "")),
				size = entry.bytes > 0 and Format.size(entry.bytes) or "—"})
		end
	end
	local reversed = {}
	for index = #rows, 1, -1 do table.insert(reversed, rows[index]) end
	return reversed
end

return OperationLog
