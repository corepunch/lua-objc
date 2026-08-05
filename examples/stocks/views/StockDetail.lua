local ns = require("AppKit")

local Views = {}
local LAYOUT = {
	metricSpacing = 4,
	metricLabelSize = 11,
	metricValueSize = 12,
	metricGridHeight = 72,
	newsCardHeight = 64,
	newsColumnSpacing = 22,
	pagePadding = 18,
	pageSpacing = 9,
	pageTitleSize = 26,
	pageSubtitleSize = 13,
	symbolSize = 20,
	nameSize = 13,
	priceSize = 34,
	changeSize = 15,
	sectionTitleSize = 14,
	compactSpacing = 2,
	summarySpacing = 14,
	metricGroupSpacing = 12,
}

local function metricRow(title, value)
	return ns.HStack {
		fillWidth = true,
		spacing = LAYOUT.metricSpacing,
		ns.Text { title, size = LAYOUT.metricLabelSize,
			weight = "semibold", color = "secondary" },
		ns.Spacer {},
		ns.Text { value, size = LAYOUT.metricValueSize, weight = "semibold" },
	}
end

local function metricColumn(rows)
	return ns.VStack {
		flexGrow = 1,
		spacing = LAYOUT.metricSpacing,
		alignment = "leading",
		ns.ForEach(rows, function(row)
			return metricRow(row[1], row[2])
		end),
	}
end

local function newsCard(article)
	return ns.VStack {
		fixedHeight = LAYOUT.newsCardHeight,
		fillWidth = true,
		spacing = 2,
		alignment = "leading",
		ns.Text { article.source, size = 10, color = "secondary" },
		ns.Text { article.title, size = 13, weight = "semibold",
			lineLimit = 2, fixedHeight = 32, fillWidth = true },
		ns.Text { article.time, size = 10, color = "secondary" },
	}
end

function Views.newsGrid(articles)
	local columns = {{}, {}}
	for index, article in ipairs(articles or {}) do
		columns[(index - 1) % 2 + 1][#columns[(index - 1) % 2 + 1] + 1] = article
	end
	return ns.HStack {
		fillWidth = true,
		flexGrow = 1,
		spacing = LAYOUT.newsColumnSpacing,
		alignment = "top",
		ns.ForEach(columns, function(column)
			return ns.VStack {
				flexGrow = 1,
				spacing = LAYOUT.pageSpacing,
				alignment = "leading",
				ns.ForEach(column, newsCard),
			}
		end),
	}
end

function Views.newsPage(articles)
	return ns.VStack {
		flexGrow = 1,
		padding = LAYOUT.pagePadding,
		spacing = LAYOUT.pageSpacing,
		alignment = "leading",
		ns.Text { "Business News", size = LAYOUT.pageTitleSize, weight = "bold" },
		ns.Text { "Latest market and company stories",
			size = LAYOUT.pageSubtitleSize, color = "secondary" },
		Views.newsGrid(articles),
	}
end

function Views.stock(stock, chart)
	return ns.VStack {
		flexGrow = 1,
		padding = LAYOUT.pagePadding,
		spacing = LAYOUT.pageSpacing,
		alignment = "leading",
		ns.VStack {
			fixedHeight = 42,
			flexShrink = 0,
			spacing = LAYOUT.compactSpacing,
			alignment = "leading",
			ns.Text { stock.symbol, size = LAYOUT.symbolSize, weight = "bold" },
			ns.Text { stock.name, size = LAYOUT.nameSize, color = "secondary" },
		},
		ns.HStack {
			flexShrink = 0,
			spacing = LAYOUT.summarySpacing,
			alignment = "bottom",
			ns.Text { stock.priceStr, size = LAYOUT.priceSize, weight = "light" },
			ns.Text { stock.changeStr, size = LAYOUT.changeSize,
				color = stock.changeColor },
		},
		chart,
		ns.HStack {
			fillWidth = true,
			fixedHeight = LAYOUT.metricGridHeight,
			flexShrink = 0,
			spacing = LAYOUT.metricGroupSpacing,
			alignment = "top",
			metricColumn {
				{"Open", stock.openStr},
				{"High", stock.dailyHighStr},
				{"Low", stock.dailyLowStr},
			},
			ns.Divider { orientation = "vertical" },
			metricColumn {
				{"Vol", stock.volumeStr},
				{"P/E", "--"},
				{"Mkt Cap", stock.marketCapStr},
			},
			ns.Divider { orientation = "vertical" },
			metricColumn {
				{"52W H", stock.fiftyTwoWeekHighStr},
				{"52W L", stock.fiftyTwoWeekLowStr},
				{"Avg Vol", stock.volumeStr},
			},
			ns.Divider { orientation = "vertical" },
			metricColumn {
				{"Yield", "--"},
				{"Beta", "--"},
				{"EPS", "--"},
			},
		},
		ns.Divider {},
		ns.Text { "Related News", size = LAYOUT.sectionTitleSize,
			weight = "semibold" },
		Views.newsGrid(stock.news),
	}
end

return Views
