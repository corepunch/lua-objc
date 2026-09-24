// Both platforms use the same row packing for measurement and placement.
// Frames use a top-leading origin; the platform converts to its view coordinates.
static CGSize flow_layout(CGSize *sizes, CGRect *frames, NSUInteger count,
	CGFloat width, CGFloat spacing, NSUInteger maxRows) {
	CGSize result = CGSizeZero;
	NSUInteger first = 0;
	NSUInteger rows = 0;
	if (frames) for (NSUInteger i = 0; i < count; i++) frames[i] = CGRectNull;
	while (first < count) {
		if (maxRows > 0 && rows >= maxRows) break;
		if (maxRows > 0 && sizes[first].width > width) break;
		NSUInteger end = first;
		CGFloat rowWidth = 0, rowHeight = 0;
		while (end < count) {
			CGFloat nextWidth = rowWidth + (end > first ? spacing : 0) + sizes[end].width;
			if (end > first && nextWidth > width) break;
			rowWidth = nextWidth;
			rowHeight = MAX(rowHeight, sizes[end].height);
			end++;
		}
		CGFloat x = 0;
		for (NSUInteger i = first; i < end; i++) {
			if (frames) frames[i] = CGRectMake(x, result.height + (rowHeight - sizes[i].height) / 2,
				sizes[i].width, sizes[i].height);
			x += sizes[i].width + spacing;
		}
		result.width = MAX(result.width, rowWidth);
		rows++;
		result.height += rowHeight + (end < count && (maxRows == 0 || rows < maxRows) ? spacing : 0);
		first = end;
	}
	return result;
}
