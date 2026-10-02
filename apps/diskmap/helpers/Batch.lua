local Format = require("apps.diskmap.helpers.Format")
local Batch = {}

-- The one flow every batch cleanup follows (simulator devices, worktrees):
-- the caller confirms the whole set once, then each item is read again,
-- revalidated and only then acted on. A refused or failed item is reported
-- and the rest continue; nothing is forced. Pure control flow: reading state,
-- validating and executing are the caller's functions, so the flow is tested
-- without a device or a repository.
--
--   options.refresh(item, done(fresh))   optional; the item's current state
--   options.validate(item, fresh)        -> true | false, {message = …}
--   options.execute(item, done(ok, output))
--   options.label(item), options.bytes(item)
function Batch.run(items, options, completion)
	local result = {removed = 0, bytes = 0, skipped = {}, failed = {}}
	local function step(index)
		local item = items[index]
		if not item then completion(result); return end
		local function proceed(fresh)
			local ok, reason = options.validate(item, fresh)
			if not ok then
				table.insert(result.skipped, options.label(item) .. " (" .. (reason and reason.message or "no longer eligible") .. ")")
				step(index + 1); return
			end
			options.execute(item, function(success, output)
				if success then
					result.removed = result.removed + 1
					result.bytes = result.bytes + (options.bytes(item) or 0)
				else
					table.insert(result.failed, options.label(item) .. " (" .. (tostring(output):gsub("\n.*", ""):sub(1, 100)) .. ")")
				end
				step(index + 1)
			end)
		end
		if options.refresh then options.refresh(item, proceed) else proceed(item) end
	end
	step(1)
end

-- "Removed 2 worktrees (366 MB). Skipped … Failed …" in one sentence list.
function Batch.report(result, verb, noun)
	local parts = {}
	if result.removed > 0 then table.insert(parts, verb .. " " .. Format.plural(result.removed, noun) .. " (" .. Format.size(result.bytes) .. ")") end
	if #result.skipped > 0 then table.insert(parts, "Skipped " .. table.concat(result.skipped, "; ")) end
	if #result.failed > 0 then table.insert(parts, "Failed " .. table.concat(result.failed, "; ")) end
	if #parts == 0 then parts[1] = "Nothing was " .. verb:lower() end
	return table.concat(parts, ". ")
end

return Batch
