/* Agent-readable dump of AppKit's computed hierarchy and table geometry. */

static NSString *layout_xml_escape(NSString *value) {
	if (!value) return @"";
	NSMutableString *out = [value mutableCopy];
	[out replaceOccurrencesOfString:@"&" withString:@"&amp;"
		options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\"" withString:@"&quot;"
		options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"<" withString:@"&lt;"
		options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@">" withString:@"&gt;"
		options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\n" withString:@"&#10;"
		options:0 range:NSMakeRange(0, out.length)];
	return out;
}

static NSString *layout_indent(NSUInteger depth) {
	return [@"  " stringByPaddingToLength:depth * 2
		withString:@"  " startingAtIndex:0];
}

static void append_layout_view(NSMutableString *out, NSView *view,
	NSUInteger depth) {
	[view layoutSubtreeIfNeeded];
	NSRect frame = view.frame;
	NSSize intrinsic = view.intrinsicContentSize;
	NSSize fitting = view.fittingSize;
	const CGFloat tolerance = kLayoutDebugGeometryTolerance;
	BOOL outside = view.superview &&
		(NSMinX(frame) < NSMinX(view.superview.bounds) - tolerance ||
		 NSMinY(frame) < NSMinY(view.superview.bounds) - tolerance ||
		 NSMaxX(frame) > NSMaxX(view.superview.bounds) + tolerance ||
		 NSMaxY(frame) > NSMaxY(view.superview.bounds) + tolerance);
	BOOL contentClipped = intrinsic.width != NSViewNoIntrinsicMetric &&
		intrinsic.width > frame.size.width + kLayoutDebugGeometryTolerance;
	NSString *text = [view isKindOfClass:NSTextField.class]
		? ((NSTextField *)view).stringValue : nil;
	[out appendFormat:
		@"%@<View class=\"%@\" x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" intrinsicWidth=\"%.1f\" intrinsicHeight=\"%.1f\" fittingWidth=\"%.1f\" fittingHeight=\"%.1f\" clipsToBounds=\"%@\" outsideParent=\"%@\" contentClipped=\"%@\"%@>\n",
		layout_indent(depth), NSStringFromClass(view.class),
		frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
		intrinsic.width, intrinsic.height, fitting.width, fitting.height,
		view.clipsToBounds ? @"true" : @"false",
		outside ? @"true" : @"false",
		contentClipped ? @"true" : @"false",
		text ? [NSString stringWithFormat:@" text=\"%@\"", layout_xml_escape(text)] : @""];

	if ([view isKindOfClass:NSTableView.class]) {
		NSTableView *table = (NSTableView *)view;
		NSInteger rows = MIN(table.numberOfRows, kLayoutDebugMaxTableRows);
		for (NSUInteger columnIndex = 0;
			 columnIndex < table.tableColumns.count; columnIndex++) {
			NSTableColumn *column = table.tableColumns[columnIndex];
			[out appendFormat:
				@"%@<Column id=\"%@\" width=\"%.1f\" minWidth=\"%.1f\" />\n",
				layout_indent(depth + 1), layout_xml_escape(column.identifier),
				column.width, column.minWidth];
			for (NSInteger row = 0; row < rows; row++) {
				NSRect cellFrame = [table frameOfCellAtColumn:(NSInteger)columnIndex row:row];
				NSView *cell = [table viewAtColumn:(NSInteger)columnIndex
					row:row makeIfNecessary:YES];
				NSTextField *label = [cell isKindOfClass:NSTableCellView.class]
					? ((NSTableCellView *)cell).textField : nil;
				[cell layoutSubtreeIfNeeded];
				BOOL clipped = label && label.intrinsicContentSize.width
					> label.frame.size.width + kLayoutDebugGeometryTolerance;
				[out appendFormat:
					@"%@<Cell row=\"%ld\" column=\"%@\" x=\"%.1f\" width=\"%.1f\" textWidth=\"%.1f\" textFrameWidth=\"%.1f\" cropped=\"%@\" text=\"%@\" />\n",
					layout_indent(depth + 1), (long)row,
					layout_xml_escape(column.identifier), cellFrame.origin.x,
					cellFrame.size.width, label.intrinsicContentSize.width,
					label.frame.size.width, clipped ? @"true" : @"false",
					layout_xml_escape(label.stringValue)];
			}
		}
	}
	for (NSView *child in view.subviews) {
		append_layout_view(out, child, depth + 1);
	}
	[out appendFormat:@"%@</View>\n", layout_indent(depth)];
}

static BOOL write_layout_debug_dump(NSWindow *window, const char *path) {
	if (!window || !path) return NO;
	NSView *root = window.contentView;
	layout_recursive(root, root.bounds.size.width);
	[root layoutSubtreeIfNeeded];
	[root displayIfNeeded];
	NSMutableString *out = [NSMutableString stringWithString:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Layout>\n"];
	append_layout_view(out, root, 1);
	[out appendString:@"</Layout>\n"];
	return [out writeToFile:[NSString stringWithUTF8String:path]
		atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
