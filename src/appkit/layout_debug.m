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

/* Points are rounded to tenths, and whole values drop the ".0" so frames
 * read as "0 0 1440 900". A rounded -0 prints as 0. */
static NSString *layout_number(CGFloat value) {
	NSString *text = [NSString stringWithFormat:@"%.1f", value];
	if ([text hasSuffix:@".0"]) text = [text substringToIndex:text.length - 2];
	return [text isEqualToString:@"-0"] ? @"0" : text;
}

static NSString *layout_rect(NSRect rect) {
	return [NSString stringWithFormat:@"%@ %@ %@ %@",
		layout_number(rect.origin.x), layout_number(rect.origin.y),
		layout_number(rect.size.width), layout_number(rect.size.height)];
}

static NSString *layout_size(NSSize size) {
	return [NSString stringWithFormat:@"%@ %@",
		layout_number(size.width), layout_number(size.height)];
}

static NSString *layout_indent(NSUInteger depth) {
	return [@"  " stringByPaddingToLength:depth * 2
		withString:@"  " startingAtIndex:0];
}

static BOOL layout_text_has_insufficient_space(NSTextField *field) {
	if (!field || field.stringValue.length == 0) return NO;
	if (field.lineBreakMode == NSLineBreakByWordWrapping
		|| field.lineBreakMode == NSLineBreakByCharWrapping) {
		NSRect required = [field.attributedStringValue boundingRectWithSize:
			NSMakeSize(field.bounds.size.width, CGFLOAT_MAX)
			options:NSStringDrawingUsesLineFragmentOrigin
				| NSStringDrawingUsesFontLeading];
		return ceil(required.size.height)
			> field.bounds.size.height + kLayoutDebugGeometryTolerance;
	}
	NSCell *cell = field.cell;
	NSRect expansion = [cell expansionFrameWithFrame:field.bounds inView:field];
	if (!NSIsEmptyRect(expansion)
		&& (expansion.size.width
			> field.bounds.size.width + kLayoutDebugGeometryTolerance
			|| expansion.size.height
			> field.bounds.size.height + kLayoutDebugGeometryTolerance)) {
		return YES;
	}
	return field.intrinsicContentSize.width
		> field.bounds.size.width + kLayoutDebugGeometryTolerance;
}

static BOOL layout_text_uses_ellipsis(NSTextField *field) {
	if (!layout_text_has_insufficient_space(field)) return NO;
	NSLineBreakMode mode = field.lineBreakMode;
	return mode == NSLineBreakByTruncatingHead
		|| mode == NSLineBreakByTruncatingTail
		|| mode == NSLineBreakByTruncatingMiddle;
}

/* Converts a rect in `view` to the dump root's top-left coordinates, which
 * match a window capture pixel for point: tools that cut pieces out of a
 * `--screenshot` look views up by identifier instead of measuring them. */
static NSRect layout_window_rect(NSView *view, NSRect rect, NSView *root) {
	NSRect converted = [view convertRect:rect toView:root];
	if (!root.isFlipped) converted.origin.y = NSHeight(root.bounds) - NSMaxY(converted);
	return converted;
}

static CGFloat layout_cell_number(NSDictionary *cell, NSString *key) {
	id value = cell[key];
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}

static void append_layout_view(NSMutableString *out, NSView *view,
	NSView *root, NSUInteger depth) {
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
	if (text) {
		contentClipped = layout_text_has_insufficient_space(
			(NSTextField *)view);
	}
	/* A hidden view shows nothing, so nothing of it is clipped: a cell
	 * template keeps the views of its other states hidden and unplaced. */
	if (view.hiddenOrHasHiddenAncestor) contentClipped = NO;
	BOOL insufficientTextSpace = text && !view.hiddenOrHasHiddenAncestor
		? layout_text_has_insufficient_space((NSTextField *)view) : NO;
	BOOL ellipsis = text
		? layout_text_uses_ellipsis((NSTextField *)view) : NO;
	NSString *identifier = view.accessibilityIdentifier;
	NSRect windowFrame = layout_window_rect(view, view.bounds, root);
	[out appendFormat:
		@"%@<View class=\"%@\"%@ frame=\"%@\" window=\"%@\" intrinsic=\"%@\" fitting=\"%@\" clipsToBounds=\"%@\" outsideParent=\"%@\" contentClipped=\"%@\"%@%@%@>\n",
		layout_indent(depth), NSStringFromClass(view.class),
		identifier ? [NSString stringWithFormat:@" identifier=\"%@\"",
			layout_xml_escape(identifier)] : @"",
		layout_rect(frame), layout_rect(windowFrame),
		layout_size(intrinsic), layout_size(fitting),
		view.clipsToBounds ? @"true" : @"false",
		outside ? @"true" : @"false",
		contentClipped ? @"true" : @"false",
		text ? [NSString stringWithFormat:@" insufficientTextSpace=\"%@\"",
			insufficientTextSpace ? @"true" : @"false"] : @"",
		text ? [NSString stringWithFormat:@" ellipsis=\"%@\"",
			ellipsis ? @"true" : @"false"] : @"",
		text ? [NSString stringWithFormat:@" text=\"%@\"", layout_xml_escape(text)] : @""];

	if ([view isKindOfClass:NSTableView.class]) {
		NSTableView *table = (NSTableView *)view;
		NSInteger rows = MIN(table.numberOfRows, kLayoutDebugMaxTableRows);
		for (NSUInteger columnIndex = 0;
			 columnIndex < table.tableColumns.count; columnIndex++) {
			NSTableColumn *column = table.tableColumns[columnIndex];
			[out appendFormat:
				@"%@<Column id=\"%@\" width=\"%@\" minWidth=\"%@\" />\n",
				layout_indent(depth + 1), layout_xml_escape(column.identifier),
				layout_number(column.width), layout_number(column.minWidth)];
			for (NSInteger row = 0; row < rows; row++) {
				NSRect cellFrame = [table frameOfCellAtColumn:(NSInteger)columnIndex row:row];
				NSView *cell = [table viewAtColumn:(NSInteger)columnIndex
					row:row makeIfNecessary:YES];
				NSTextField *label = [cell isKindOfClass:NSTableCellView.class]
					? ((NSTableCellView *)cell).textField : nil;
				/* Icon-only cells keep their title as tooltip text only. */
				if (label.hidden) label = nil;
				[cell layoutSubtreeIfNeeded];
				BOOL clipped = label
					&& layout_text_has_insufficient_space(label);
				BOOL cellEllipsis = label && layout_text_uses_ellipsis(label);
				[out appendFormat:
					@"%@<Cell row=\"%ld\" column=\"%@\" x=\"%@\" width=\"%@\" textWidth=\"%@\" textFrameWidth=\"%@\" cropped=\"%@\" ellipsis=\"%@\" text=\"%@\" />\n",
					layout_indent(depth + 1), (long)row,
					layout_xml_escape(column.identifier),
					layout_number(cellFrame.origin.x),
					layout_number(cellFrame.size.width),
					layout_number(label.intrinsicContentSize.width),
					layout_number(label.frame.size.width), clipped ? @"true" : @"false",
					cellEllipsis ? @"true" : @"false",
					layout_xml_escape(label.stringValue)];
			}
		}
	}
	/* The treemap paints cells laid out in Lua (lua/ui/treemap.lua) rather
	 * than child views; list them so their geometry is inspectable too. */
	Class treemapClass = NSClassFromString(@"LuaTreemapView");
	if (treemapClass && [view isKindOfClass:treemapClass]) {
		for (NSDictionary *cell in [view valueForKey:@"cells"]) {
			if (![cell isKindOfClass:NSDictionary.class]) continue;
			NSRect cellFrame = layout_window_rect(view, NSMakeRect(
				layout_cell_number(cell, @"x"), layout_cell_number(cell, @"y"),
				layout_cell_number(cell, @"w"), layout_cell_number(cell, @"h")), root);
			NSString *label = [cell[@"label"] isKindOfClass:NSString.class] ? cell[@"label"] : @"";
			[out appendFormat:
				@"%@<TreemapCell id=\"%@\" depth=\"%.0f\" window=\"%@\" label=\"%@\" />\n",
				layout_indent(depth + 1), layout_xml_escape([cell[@"id"] description]),
				layout_cell_number(cell, @"depth"), layout_rect(cellFrame),
				layout_xml_escape(label)];
		}
	}
	for (NSView *child in view.subviews) {
		append_layout_view(out, child, root, depth + 1);
	}
	[out appendFormat:@"%@</View>\n", layout_indent(depth)];
}

/* `scale` is the window's backing scale: pixels per point in a capture of
 * the same window (see write_window_capture). */
static BOOL write_layout_debug_dump(NSWindow *window, const char *path) {
	if (!window || !path) return NO;
	NSView *root = window.contentView;
	layout_recursive(root, root.bounds.size.width);
	[root layoutSubtreeIfNeeded];
	[root displayIfNeeded];
	NSMutableString *out = [NSMutableString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Layout scale=\"%@\">\n",
		layout_number(window.backingScaleFactor)];
	append_layout_view(out, root, root, 1);
	[out appendString:@"</Layout>\n"];
	return [out writeToFile:[NSString stringWithUTF8String:path]
		atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

/* --capture=<prefix>: one settled moment of a window, for tools that cut its
 * pixels by view (such as modules/reel). <prefix>.layout.xml is the layout
 * dump and <prefix>.png is exactly the dump's root, the content view, at
 * backing scale, so a dump rect times `scale` is a pixel rect. WindowServer
 * does the capture because it composites materials and vibrancy that
 * offscreen view rendering drops; `-o` leaves out the window shadow, and
 * the image is cropped to the content view for windows with a separate
 * title bar. The corners stay transparent where the window is rounded. */
static BOOL write_window_capture(NSWindow *window, const char *prefix) {
	if (!window || !prefix) return NO;
	NSString *base = [NSString stringWithUTF8String:prefix];
	NSString *layoutPath = [base stringByAppendingString:@".layout.xml"];
	NSString *imagePath = [base stringByAppendingString:@".png"];
	[[NSFileManager defaultManager] createDirectoryAtPath:base.stringByDeletingLastPathComponent
		withIntermediateDirectories:YES attributes:nil error:nil];
	if (!write_layout_debug_dump(window, layoutPath.fileSystemRepresentation)) return NO;
	[window display];
	NSString *shot = [NSTemporaryDirectory() stringByAppendingPathComponent:
		[NSUUID.UUID.UUIDString stringByAppendingString:@".png"]];
	NSTask *task = [[NSTask alloc] init];
	task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
	task.arguments = @[@"-x", @"-o", @"-l", @(window.windowNumber).stringValue, shot];
	if (![task launchAndReturnError:nil]) return NO;
	[task waitUntilExit];
	NSData *data = task.terminationStatus == 0 ? [NSData dataWithContentsOfFile:shot] : nil;
	[[NSFileManager defaultManager] removeItemAtPath:shot error:nil];
	NSBitmapImageRep *full = data ? [NSBitmapImageRep imageRepWithData:data] : nil;
	if (!full.CGImage) return NO;
	CGFloat scale = window.backingScaleFactor;
	NSSize frameSize = window.frame.size;
	if (full.pixelsWide != (NSInteger)llround(frameSize.width * scale)
		|| full.pixelsHigh != (NSInteger)llround(frameSize.height * scale)) {
		fprintf(stderr, "capture: window image is %ldx%ld px, expected %.0fx%.0f\n",
			(long)full.pixelsWide, (long)full.pixelsHigh,
			frameSize.width * scale, frameSize.height * scale);
		return NO;
	}
	NSRect content = [window.contentView convertRect:window.contentView.bounds toView:nil];
	CGRect crop = CGRectMake(llround(NSMinX(content) * scale),
		llround((frameSize.height - NSMaxY(content)) * scale),
		llround(NSWidth(content) * scale), llround(NSHeight(content) * scale));
	CGImageRef cropped = CGImageCreateWithImageInRect(full.CGImage, crop);
	if (!cropped) return NO;
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cropped];
	CGImageRelease(cropped);
	NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
	return [png writeToFile:imagePath atomically:YES];
}
