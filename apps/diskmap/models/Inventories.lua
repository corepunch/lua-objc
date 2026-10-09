local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Applications = require("apps.diskmap.models.Applications")
local Worktrees = require("apps.diskmap.helpers.Worktrees")
local Simulators = require("apps.diskmap.helpers.Simulators")
local SimulatorPlan = require("apps.diskmap.helpers.SimulatorPlan")
local Format = require("apps.diskmap.helpers.Format")
local Inventories = Model:extend("inventories")

function Inventories:state(id)
	return self:find(id) or self:create({id = id, rows = {}, entries = {}, facts = {}, inventory = {}, keep = {}})
end

function Inventories:applicationsSummary()
	if not Model.db.files or Model.db.files.measuring then return nil end
	return Applications.summary(Applications:rows(), Applications:leftovers())
end

function Inventories:rebuildWorktrees()
	local stock = self:state("worktrees")
	for path, facts in pairs(stock.facts) do
		local total = 0
		for _, row in ipairs(Locations:leaves()) do
			if row.artifact and row.path and row.path:sub(1, #path + 1) == path .. "/" then
				local measured = Model.db.measurements[row.id]
				total = total + (measured and measured.bytes or 0)
			end
		end
		facts.generatedBytes = math.max(facts.generatedBytes or 0, total)
	end
	stock.rows = Worktrees.rows(stock.entries, stock.facts, {now = os.time(), kept = function(path) return Locations.keeps("worktree:" .. path) end})
	local plan = Worktrees.plan(stock.rows)
	Model.db.worktreePlan = {removalBytes = plan.removalBytes, removalCount = #plan.removal, reviewBytes = plan.reviewBytes,
		reviewCount = #plan.review, pruneCount = #plan.prune}
end

function Inventories:simulatorPlan()
	local stock = self:state("simulators")
	local plan = SimulatorPlan.build(stock.inventory, {runtime = stock.chosenRuntime, keep = stock.keep,
		protected = function(udid)
			local catalog = Locations:find("simulators")
			return (catalog and catalog:isKept()) or Locations.keeps(Simulators.keepKey(udid))
		end})
	Model.db.simulatorPlan = stock.loaded and {removalBytes = plan.removalBytes, removalCount = #plan.removal,
		blockedBytes = plan.blockedBytes, complete = plan.complete, runtime = plan.runtime} or nil
	return plan
end

function Inventories:xcodeBadge()
	local stock = self:state("xcode")
	if not stock.loaded then return nil end
	local total = 0
	for _, rows in pairs(stock.rows) do for _, row in ipairs(rows) do total = total + (row.bytes or 0) end end
	return total > 0 and Format.size(total) or nil
end

return Inventories
