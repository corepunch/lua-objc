#pragma mark - Paragraph (long-form text)

/* Native selectable prose with explicit leading and optional hyphenation. */
@interface LuaParagraphView : NSTextView <NSTextViewDelegate, LuaParagraphText>
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSFont *bodyFont;
@property(nonatomic, strong) NSColor *bodyColor;
@property(nonatomic) NSInteger textAlignment;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) BOOL hyphenation;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
@property(nonatomic, copy) NSArray<NSDictionary *> *boldRanges;
@property(nonatomic, copy) NSArray<NSDictionary *> *italicRanges;
/* The colour of a link's words. */
@property(nonatomic, strong) NSColor *linkColor;
@property(nonatomic) NSInteger revealedCharacters;
/* Set once the view is initialized; see -rebuild. */
@property(nonatomic) BOOL ready;
- (NSSize)sizeForProposedWidth:(CGFloat)width;
@end

@implementation LuaParagraphView

- (instancetype)init {
	NSTextStorage *storage = [[NSTextStorage alloc] init];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(0, CGFLOAT_MAX)];
	container.widthTracksTextView = YES;
	container.lineFragmentPadding = 0;
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	self = [super initWithFrame:NSZeroRect textContainer:container];
	if (!self) return nil;
	self.editable = NO;
	self.selectable = YES;
	self.drawsBackground = NO;
	self.richText = NO;
	self.textContainerInset = NSZeroSize;
	// The layout engine owns the frame; the text view must not grow itself.
	self.verticallyResizable = NO;
	self.horizontallyResizable = NO;
	_text = @"";
	_bodyFont = [NSFont systemFontOfSize:NSFont.systemFontSize];
	_bodyColor = NSColor.labelColor;
	_textAlignment = NSTextAlignmentNatural;
	_links = @[];
	_revealedCharacters = -1;
	/* The text view reports clicks on links to its delegate; the paragraph
	 * styles them itself, so a link changes only the pointer. */
	self.delegate = self;
	self.linkTextAttributes = @{NSCursorAttributeName: NSCursor.pointingHandCursor};
	_ready = YES;
	[self rebuild];
	return self;
}

- (void)setText:(NSString *)text { _text = [text copy] ?: @""; [self rebuild]; }
- (NSString *)paragraphText { return _text; }
- (void)setBodyFont:(NSFont *)font { _bodyFont = font ?: _bodyFont; [self rebuild]; }
- (void)setBodyColor:(NSColor *)color { _bodyColor = color ?: NSColor.labelColor; [self rebuild]; }
- (void)setTextAlignment:(NSInteger)alignment { _textAlignment = alignment; [self rebuild]; }
- (void)setLineSpacing:(CGFloat)value { _lineSpacing = MAX(0, value); [self rebuild]; }
- (void)setHyphenation:(BOOL)value { _hyphenation = value; [self rebuild]; }
- (void)setLinks:(NSArray<LuaParagraphLink *> *)links { _links = [links copy] ?: @[]; [self rebuild]; }
- (void)setBoldRanges:(NSArray<NSDictionary *> *)ranges { _boldRanges = [ranges copy] ?: @[]; [self rebuild]; }
- (void)setItalicRanges:(NSArray<NSDictionary *> *)ranges { _italicRanges = [ranges copy] ?: @[]; [self rebuild]; }
- (void)setLinkColor:(NSColor *)color { _linkColor = color; [self applyReveal]; }
- (id)paragraphLinkColor { return _linkColor ?: NSColor.controlAccentColor; }

/* A typewriter reveal. The whole paragraph is always laid out, so words never
 * jump between lines as they appear — the approach of SwiftUI typewriter
 * effects built on TextRenderer. Unrevealed characters are drawn clear and
 * still take their space: the paragraph measures as its whole text from the
 * first character, so a page makes room for an answer once and a reveal
 * never re-lays anything out. */
- (void)setRevealedCharacters:(NSInteger)value {
	value = MAX(-1, value);
	if (value == _revealedCharacters) return;
	_revealedCharacters = value;
	[self applyReveal];
}
/* Lua writes `font` and `textColor` as it does for labels. */
- (NSFont *)font { return _bodyFont; }
- (void)setFont:(NSFont *)font { if (font && _ready) self.bodyFont = font; else [super setFont:font]; }
- (NSColor *)textColor { return _bodyColor; }
- (void)setTextColor:(NSColor *)color { if (_ready) self.bodyColor = color; else [super setTextColor:color]; }

- (void)chooseLinkItem:(NSMenuItem *)item {
	[(LuaParagraphLink *)item.representedObject performItem:(NSUInteger)item.tag];
}

- (NSMenu *)menuForLink:(LuaParagraphLink *)link {
	NSMenu *menu = [[NSMenu alloc] initWithTitle:link.label ?: @""];
	menu.autoenablesItems = NO;
	[link.titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
		NSMenuItem *item = [menu addItemWithTitle:title action:@selector(chooseLinkItem:) keyEquivalent:@""];
		NSString *symbol = index < link.symbols.count ? link.symbols[index] : @"";
		if (symbol.length) item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
		item.target = self;
		item.tag = (NSInteger)index;
		item.representedObject = link;
		item.enabled = [link.callbacks[index] isKindOfClass:LuaReg.class];
	}];
	return menu;
}

/* A click on a link opens its menu below the words, as a pull-down does. */
- (BOOL)textView:(__unused NSTextView *)textView clickedOnLink:(__unused id)value atIndex:(NSUInteger)index {
	LuaParagraphLink *link = paragraph_link_at(self, index);
	if (!link || link.titles.count == 0) return YES;
	NSRange glyphs = [self.layoutManager glyphRangeForCharacterRange:paragraph_link_range(self, link)
		actualCharacterRange:NULL];
	NSRect words = [self.layoutManager boundingRectForGlyphRange:glyphs inTextContainer:self.textContainer];
	[[self menuForLink:link] popUpMenuPositioningItem:nil
		atLocation:NSMakePoint(NSMinX(words), NSMaxY(words)) inView:self];
	return YES;
}

- (void)applyReveal {
	paragraph_apply_reveal(self, _bodyColor, self.paragraphLinkColor, NSColor.clearColor);
	self.needsDisplay = YES;
}

- (CGFloat)bodyLineHeight {
	return ceil(_bodyFont.ascender - _bodyFont.descender + _bodyFont.leading);
}

- (NSAttributedString *)bodyString {
	return paragraph_body_string(_text, _bodyFont, _bodyColor, _lineSpacing, (NSTextAlignment)_textAlignment,
		_hyphenation, [self bodyLineHeight]);
}

- (void)rebuild {
	/* NSTextView's initializer applies its own font and colour first. */
	if (!_ready || !_bodyFont) return;
	[self.textStorage setAttributedString:[self bodyString]];
	paragraph_apply_links(self, YES);
	[self applyReveal];
	[self setAccessibilityValue:_text];
	[self invalidateIntrinsicContentSize];
	self.needsDisplay = YES;
}

/* Measurement uses a private TextKit stack so proposing a width never moves
 * the live container. Unbounded proposals return the unwrapped line. */
- (NSSize)sizeForProposedWidth:(CGFloat)width {
	/* Empty text takes no space, as SwiftUI Text(""). */
	if (_text.length == 0) return NSZeroSize;
	BOOL unbounded = width <= 0 || width >= CGFLOAT_MAX / 2;
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:self.textStorage];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(unbounded ? CGFLOAT_MAX : width, CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	[manager ensureLayoutForTextContainer:container];
	NSRect used = [manager usedRectForTextContainer:container];
	CGFloat height = NSMaxY(used);
	CGFloat scale = self.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor ?: 1;
	return NSMakeSize(ceil((unbounded ? NSMaxX(used) : width) * scale) / scale, ceil(height * scale) / scale);
}

- (NSSize)intrinsicContentSize {
	return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}
@end

static int bridge_AppKitControls_paragraph(lua_State *L) {
	LuaParagraphView *view = [[LuaParagraphView alloc] init];
	view.text = @(luaL_optstring(L, 1, ""));
	push_objc(L, view, "nsview");
	return 1;
}
