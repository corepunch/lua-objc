-- A month of personal finance: account totals, spending over time and by
-- category, and recent transactions. Sample data; nothing is saved.
local Model = {}
Model.__index = Model

Model.CATEGORIES = {
	{id = "home", name = "Home", color = "systemBlue", icon = "house.fill"},
	{id = "food", name = "Food", color = "systemOrange", icon = "fork.knife"},
	{id = "travel", name = "Travel", color = "systemTeal", icon = "airplane"},
	{id = "fun", name = "Fun", color = "systemPink", icon = "gamecontroller.fill"},
	{id = "health", name = "Health", color = "systemGreen", icon = "heart.fill"},
}

-- Spending per period, oldest first.
Model.MONTHLY = {
	{label = "Apr", value = 4310}, {label = "May", value = 3890}, {label = "Jun", value = 4760},
	{label = "Jul", value = 5120}, {label = "Aug", value = 4450}, {label = "Sep", value = 3915},
}
Model.WEEKLY = {
	{label = "W27", value = 1180}, {label = "W28", value = 940}, {label = "W29", value = 1310},
	{label = "W30", value = 1020}, {label = "W31", value = 1260}, {label = "W32", value = 870},
	{label = "W33", value = 1105}, {label = "W34", value = 990}, {label = "W35", value = 1240},
	{label = "W36", value = 760}, {label = "W37", value = 1015}, {label = "W38", value = 905},
}

Model.TRANSACTIONS = {
	{id = 1, merchant = "Blue Bottle Coffee", category = "food", date = "Today", amount = -6.50},
	{id = 2, merchant = "Salary", category = "home", date = "Today", amount = 4210.00, income = true},
	{id = 3, merchant = "Lisbon flights", category = "travel", date = "Yesterday", amount = -318.40},
	{id = 4, merchant = "Whole Foods Market", category = "food", date = "Yesterday", amount = -84.12},
	{id = 5, merchant = "Climbing gym", category = "health", date = "27 Sep", amount = -65.00},
	{id = 6, merchant = "Game Pass", category = "fun", date = "26 Sep", amount = -14.99},
	{id = 7, merchant = "Electricity", category = "home", date = "25 Sep", amount = -92.30},
}

function Model.new()
	local self = setmetatable({period = "weekly"}, Model)
	self.categories = {}
	for _, category in ipairs(Model.CATEGORIES) do self.categories[category.id] = category end
	return self
end

local function money(value, signed)
	local sign = value < 0 and "−" or (signed and "+" or "")
	local whole, cents = math.modf(math.abs(value))
	local digits = tostring(math.floor(whole)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	local hundredths = math.floor(cents * 100 + 0.5)
	-- Whole amounts read as headlines: $8,420, not $8,420.00.
	if hundredths == 0 and whole >= 1000 then return string.format("%s$%s", sign, digits) end
	return string.format("%s$%s.%02d", sign, digits, hundredths)
end
Model.money = money

-- The headline cards: label, value, change against last month.
function Model:cards()
	return {
		{id = "balance", label = "Balance", value = money(24180.52), change = "+$1,204 this month", color = "secondary", icon = "banknote.fill"},
		{id = "income", label = "Income", value = money(8420), change = "▲ 6% vs August", color = "systemGreen", icon = "arrow.down.circle.fill"},
		{id = "spending", label = "Spending", value = money(3915), change = "▼ 12% vs August", color = "systemGreen", icon = "arrow.up.circle.fill"},
		{id = "savings", label = "Savings rate", value = "38%", change = "Goal 35%", color = "secondary", icon = "leaf.fill"},
	}
end

function Model:setPeriod(period)
	if period == "weekly" or period == "monthly" then self.period = period end
end

-- Chart bars for the current period, heights as a share of the largest.
function Model:chart()
	local source = self.period == "weekly" and Model.WEEKLY or Model.MONTHLY
	local largest = 0
	for _, bar in ipairs(source) do largest = math.max(largest, bar.value) end
	local bars = {}
	for index, bar in ipairs(source) do
		table.insert(bars, {label = bar.label, value = bar.value, share = bar.value / largest,
			current = index == #source})
	end
	return {title = self.period == "weekly" and "Spending by week" or "Spending by month", bars = bars}
end

function Model:breakdown()
	local shares = {home = 38, food = 24, travel = 18, fun = 11, health = 9}
	local rows = {}
	for _, category in ipairs(Model.CATEGORIES) do
		table.insert(rows, {name = category.name, color = category.color, share = shares[category.id]})
	end
	return rows
end

function Model:transactions()
	local rows = {}
	for _, t in ipairs(Model.TRANSACTIONS) do
		local category = self.categories[t.category]
		table.insert(rows, {id = t.id, merchant = t.merchant, category = t.income and "Income" or category.name,
			date = t.date, amount = money(t.amount, true), income = t.income == true,
			icon = t.income and "arrow.down.circle.fill" or category.icon, color = t.income and "systemGreen" or category.color})
	end
	return rows
end

function Model:presentation()
	return {title = "Overview", month = "September 2026", cards = self:cards(), chart = self:chart(),
		breakdown = self:breakdown(), transactions = self:transactions()}
end

return Model
