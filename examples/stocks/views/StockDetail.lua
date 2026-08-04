local ns = require("AppKit")

local Views = {}
local LAYOUT = {
	metricSpacing = 3,
	metricLabelSize = 11,
	metricValueSize = 14,
	newsRowHeight = 38,
	newsTimeWidth = 48,
	pagePadding = 20,
	pageSpacing = 12,
	pageTitleSize = 26,
	pageSubtitleSize = 13,
	symbolSize = 20,
	nameSize = 13,
	priceSize = 34,
	changeSize = 15,
	sectionTitleSize = 14,
	compactSpacing = 2,
	summarySpacing = 14,
	metricGroupSpacing = 16,
}

local function metric(title, value)
	return ns.VStack {
		flexGrow = 1,
		spacing = LAYOUT.metricSpacing,
		alignment = "leading",
		ns.Text { title, size = LAYOUT.metricLabelSize, color = "secondary" },
		ns.Text { value, size = LAYOUT.metricValueSize },
	}
end

function Views.newsList(articles)
	local list = ns.List {
		flexGrow = 1,
		style = "plain",
		header = false,
		alternatingRows = false,
		rowHeight = LAYOUT.newsRowHeight,
		columns = {
			{ id = "headline", title = "Headline" },
			{ id = "time", title = "Time", width = LAYOUT.newsTimeWidth,
				alignment = "right" },
		},
	}
	local rows = {}
	for index, article in ipairs(articles or {}) do
		rows[index] = {
			_id = tostring(index),
			headline = article.title .. "  —  " .. article.source,
			time = article.time,
		}
	end
	list:replaceRows(rows)
	return list
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
		Views.newsList(articles),
	}
end

function Views.stock(stock, chart)
	return ns.VStack {
		flexGrow = 1,
		padding = LAYOUT.pagePadding,
		spacing = LAYOUT.pageSpacing,
		alignment = "leading",
		ns.VStack {
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
			flexShrink = 0,
			spacing = LAYOUT.metricGroupSpacing,
			alignment = "top",
			metric("Open", stock.openStr),
			metric("Previous Close", stock.prevCloseStr),
			metric("Day Range", stock.dayRangeStr),
		},
		ns.HStack {
			fillWidth = true,
			flexShrink = 0,
			spacing = LAYOUT.metricGroupSpacing,
			alignment = "top",
			metric("Volume", stock.volumeStr),
			metric("52 Week Range", stock.yearRangeStr),
		},
		ns.Divider {},
		ns.Text { "Related News", size = LAYOUT.sectionTitleSize,
			weight = "semibold" },
		Views.newsList(stock.news),
	}
end

return Views
