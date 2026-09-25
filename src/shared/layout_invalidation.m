/*
 * Lua property writes that change a view's measured size or its siblings'
 * placement, shared by the AppKit and UIKit setters. Paint-only writes
 * (colors, alpha, offsets, enabled state) never schedule layout, so gesture
 * handlers that update a view every frame stay cheap.
 */
static BOOL lua_objc_key_in(const char *key, NSSet<NSString *> *keys) {
	return [keys containsObject:[NSString stringWithUTF8String:key]];
}

static BOOL lua_objc_key_affects_layout(const char *key) {
	static NSSet<NSString *> *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = [NSSet setWithArray:@[
			/* content that determines intrinsic size */
			@"text", @"stringValue", @"attributedStringValue", @"attributedText",
			@"title", @"attributedTitle", @"subtitle", @"detail",
			@"placeholder", @"placeholderString", @"font", @"image",
			@"hidden", @"maximumNumberOfLines", @"numberOfLines", @"lineBreakMode",
			@"controlSize", @"bezeled", @"bordered", @"imagePosition",
			/* declarative layout attributes */
			@"padding", @"paddingHorizontal", @"paddingVertical", @"paddingLeading",
			@"paddingTrailing", @"paddingTop", @"paddingBottom", @"spacing",
			@"alignment", @"maxRows", @"fixedWidth", @"fixedHeight", @"minWidth",
			@"minHeight", @"maxWidth", @"maxHeight", @"fillWidth", @"fillHeight",
			@"flexGrow", @"flexShrink", @"flexBasis", @"scrollDisabled", @"scrollEnabled",
		]];
	});
	return lua_objc_key_in(key, keys);
}

/* Reads that must observe the layout implied by earlier writes. */
static BOOL lua_objc_key_reads_geometry(const char *key) {
	static NSSet<NSString *> *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = [NSSet setWithArray:@[
			@"frame", @"bounds", @"size", @"fittingSize", @"intrinsicContentSize",
			@"contentSize", @"visibleRect",
		]];
	});
	return lua_objc_key_in(key, keys);
}
