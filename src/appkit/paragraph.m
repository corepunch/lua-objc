#pragma mark - Paragraph (long-form text)

/* Long-form prose, set as a book sets it: selectable text with explicit
 * leading, optional hyphenation, and a figure the first lines wrap around, as
 * Zork Zero set each room's picture beside its description. NSTextField cannot
 * flow text around a shape, so this is a non-editable NSTextView on TextKit 1,
 * whose NSTextContainer.exclusionPaths carve the figure's square out of the
 * first lines — the mechanism Pages uses for floating objects. The figure is
 * an ordinary view (an image view from Lua) that the paragraph places. */
@interface LuaParagraphLayoutManager : NSLayoutManager
@end

@implementation LuaParagraphLayoutManager
- (void)drawUnderlineForGlyphRange:(NSRange)glyphRange underlineType:(NSUnderlineStyle)underlineVal
		baselineOffset:(CGFloat)baselineOffset lineFragmentRect:(NSRect)lineRect
		lineFragmentGlyphRange:(NSRange)lineGlyphRange containerOrigin:(NSPoint)containerOrigin {
	[super drawUnderlineForGlyphRange:glyphRange underlineType:underlineVal
		baselineOffset:baselineOffset + kParagraphLinkUnderlineOffset lineFragmentRect:lineRect
		lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
}
@end

@interface LuaParagraphView : NSTextView <NSTextViewDelegate, LuaParagraphLinking>
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSFont *bodyFont;
@property(nonatomic, strong) NSColor *bodyColor;
@property(nonatomic) NSInteger textAlignment;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) BOOL hyphenation;
/* A view floated at the leading edge, a square `figureLines` lines tall. */
@property(nonatomic, strong) NSView *figureView;
@property(nonatomic) NSInteger figureLines;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
/* The thicker dotted rule under a link; the words keep the body's colour. */
@property(nonatomic, strong) NSColor *linkColor;
/* Characters shown so far, counted as Lua's utf8.len counts them; -1 shows
 * the whole paragraph. See `paragraph_revealed_length`. */
@property(nonatomic) NSInteger revealedCharacters;
/* The revealed height last reported to layout. */
@property(nonatomic) CGFloat revealedBottom;
/* Set once the view is initialized; see -rebuild. */
@property(nonatomic) BOOL ready;
- (NSSize)sizeForProposedWidth:(CGFloat)width;
@end

@implementation LuaParagraphView

- (instancetype)init {
	NSTextStorage *storage = [[NSTextStorage alloc] init];
	NSLayoutManager *manager = [[LuaParagraphLayoutManager alloc] init];
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
	_figureLines = kParagraphFigureLines;
	_links = @[];
	_revealedCharacters = -1;
	/* The text view reports clicks on links to its delegate; the paragraph
	 * rules them itself, so a link changes only the pointer. */
	self.delegate = self;
	self.linkTextAttributes = @{NSCursorAttributeName: NSCursor.pointingHandCursor};
	_ready = YES;
	[self rebuild];
	return self;
}

- (void)setText:(NSString *)text { _text = [text copy] ?: @""; [self rebuild]; }
- (void)setBodyFont:(NSFont *)font { _bodyFont = font ?: _bodyFont; [self rebuild]; }
- (void)setBodyColor:(NSColor *)color { _bodyColor = color ?: NSColor.labelColor; [self rebuild]; }
- (void)setTextAlignment:(NSInteger)alignment { _textAlignment = alignment; [self rebuild]; }
- (void)setLineSpacing:(CGFloat)value { _lineSpacing = MAX(0, value); [self rebuild]; }
- (void)setHyphenation:(BOOL)value { _hyphenation = value; [self rebuild]; }
- (void)setFigureView:(NSView *)view {
	if (view == _figureView) return;
	[_figureView removeFromSuperview];
	_figureView = view;
	if (view) {
		view.wantsLayer = YES;
		view.layer.masksToBounds = YES;
		[self addSubview:view];
	}
	[self rebuild];
}
- (void)setFigureLines:(NSInteger)value { _figureLines = MAX(1, value); [self rebuild]; }
- (void)setLinks:(NSArray<LuaParagraphLink *> *)links { _links = [links copy] ?: @[]; [self rebuild]; }
- (void)setLinkColor:(NSColor *)color { _linkColor = color; [self applyReveal]; }

/* A typewriter reveal. The whole paragraph is always laid out, so words never
 * jump between lines as they appear — the approach of SwiftUI typewriter
 * effects built on TextRenderer. Unrevealed characters are drawn clear, and
 * the paragraph measures only the lines revealed so far, so a scroll view
 * anchored to its bottom follows the text line by line. Recolouring does not
 * re-lay out the text; layout is invalidated only when a new line starts. */
- (void)setRevealedCharacters:(NSInteger)value {
	value = MAX(-1, value);
	if (value == _revealedCharacters) return;
	_revealedCharacters = value;
	[self applyReveal];
	/* A paragraph being built is measured when it is first laid out. */
	if (!self.superview) return;
	CGFloat bottom = [self revealedBottomInManager:self.layoutManager container:self.textContainer];
	if (bottom != _revealedBottom) {
		_revealedBottom = bottom;
		[self invalidateIntrinsicContentSize];
		invalidate_layout(self);
	}
}
/* Lua writes `font` and `textColor` as it does for labels. */
- (NSFont *)font { return _bodyFont; }
- (void)setFont:(NSFont *)font { if (font && _ready) self.bodyFont = font; else [super setFont:font]; }
- (NSColor *)textColor { return _bodyColor; }
- (void)setTextColor:(NSColor *)color { if (_ready) self.bodyColor = color; else [super setTextColor:color]; }

/* The UTF-16 length of the revealed prefix of `text`, never splitting a
 * composed character or surrogate pair. */
static NSUInteger paragraph_revealed_length(NSString *text, NSInteger scalars) {
	if (scalars < 0) return text.length;
	NSUInteger offset = 0;
	for (; scalars > 0 && offset < text.length; scalars--)
		offset += CFStringIsSurrogateHighCharacter([text characterAtIndex:offset]) && offset + 1 < text.length ? 2 : 1;
	if (offset > 0 && offset < text.length)
		offset = NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:offset - 1]);
	return offset;
}

- (NSUInteger)revealedBodyLength {
	return paragraph_revealed_length(_text, _revealedCharacters);
}

- (NSRange)bodyRangeOfLink:(LuaParagraphLink *)link {
	NSUInteger start = paragraph_revealed_length(_text, MAX(0, link.location));
	NSUInteger end = paragraph_revealed_length(_text, MAX(0, link.location) + MAX(0, link.length));
	end = MIN(end, self.textStorage.length);
	return start < end ? NSMakeRange(start, end - start) : NSMakeRange(NSNotFound, 0);
}

- (void)applyLinks {
	NSTextStorage *storage = self.textStorage;
	[storage beginEditing];
	[_links enumerateObjectsUsingBlock:^(LuaParagraphLink *link, NSUInteger index, __unused BOOL *stop) {
		NSRange range = [self bodyRangeOfLink:link];
		if (range.location == NSNotFound) return;
		[storage addAttribute:NSLinkAttributeName value:@(index).stringValue range:range];
		[storage addAttribute:NSUnderlineStyleAttributeName
			value:@(NSUnderlineStyleThick | NSUnderlineStylePatternDot) range:range];
	}];
	[storage endEditing];
}

- (LuaParagraphLink *)linkAtCharacterIndex:(NSUInteger)index {
	if (index >= MIN([self revealedBodyLength], self.textStorage.length)) return nil;
	for (LuaParagraphLink *link in _links)
		if (NSLocationInRange(index, [self bodyRangeOfLink:link])) return link;
	return nil;
}

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
	LuaParagraphLink *link = [self linkAtCharacterIndex:index];
	if (!link || link.titles.count == 0) return YES;
	NSRange glyphs = [self.layoutManager glyphRangeForCharacterRange:[self bodyRangeOfLink:link]
		actualCharacterRange:NULL];
	NSRect words = [self.layoutManager boundingRectForGlyphRange:glyphs inTextContainer:self.textContainer];
	[[self menuForLink:link] popUpMenuPositioningItem:nil
		atLocation:NSMakePoint(NSMinX(words), NSMaxY(words)) inView:self];
	return YES;
}

- (void)applyReveal {
	NSTextStorage *storage = self.textStorage;
	NSUInteger shown = MIN([self revealedBodyLength], storage.length);
	[storage beginEditing];
	[storage addAttribute:NSForegroundColorAttributeName value:_bodyColor range:NSMakeRange(0, shown)];
	[storage addAttribute:NSForegroundColorAttributeName value:NSColor.clearColor
		range:NSMakeRange(shown, storage.length - shown)];
	/* A link is ruled only under the words typed so far. */
	for (LuaParagraphLink *link in _links) {
		NSRange range = [self bodyRangeOfLink:link];
		if (range.location == NSNotFound) continue;
		NSRange visible = NSIntersectionRange(range, NSMakeRange(0, shown));
		[storage addAttribute:NSUnderlineColorAttributeName value:NSColor.clearColor range:range];
		if (visible.length) [storage addAttribute:NSUnderlineColorAttributeName
			value:_linkColor ?: NSColor.controlAccentColor range:visible];
	}
	[storage endEditing];
	_figureView.hidden = _revealedCharacters == 0;
	self.needsDisplay = YES;
}

/* The bottom of the last revealed line; the whole text's height once the
 * reveal reaches the last line, so a finished reveal measures as unrevealed
 * text does. A revealed figure still reserves its lines. */
- (CGFloat)revealedBottomInManager:(NSLayoutManager *)manager container:(NSTextContainer *)container {
	if (_revealedCharacters == 0 || _text.length == 0) return 0;
	[manager ensureLayoutForTextContainer:container];
	CGFloat bottom = NSMaxY([manager usedRectForTextContainer:container]);
	NSUInteger body = [self revealedBodyLength];
	if (_revealedCharacters > 0 && body < manager.textStorage.length) {
		if (body == 0) bottom = 0;
		else {
			NSRange line;
			NSRect used = [manager lineFragmentUsedRectForGlyphAtIndex:
				[manager glyphIndexForCharacterAtIndex:body - 1] effectiveRange:&line];
			if (NSMaxRange(line) < manager.numberOfGlyphs) bottom = NSMaxY(used);
		}
	}
	if (_figureView) bottom = MAX(bottom, [self figureSide]);
	return bottom;
}

- (CGFloat)bodyLineHeight {
	return ceil(_bodyFont.ascender - _bodyFont.descender + _bodyFont.leading);
}

- (NSAttributedString *)bodyString {
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.lineSpacing = _lineSpacing;
	style.alignment = (NSTextAlignment)_textAlignment;
	style.hyphenationFactor = _hyphenation ? 1.0 : 0.0;
	/* Fixed line heights keep the lines beside the figure on the same
	 * pitch the figure was sized for. */
	style.minimumLineHeight = style.maximumLineHeight = [self bodyLineHeight];
	return [[NSAttributedString alloc] initWithString:_text attributes:@{
		NSFontAttributeName: _bodyFont,
		NSForegroundColorAttributeName: _bodyColor,
		NSParagraphStyleAttributeName: style,
	}];
}

/* The figure spans exactly `figureLines` lines, from the first line's top to
 * the last line's bottom, and is as wide as it is tall. */
- (CGFloat)figureSide {
	return _figureLines * ([self bodyLineHeight] + _lineSpacing) - _lineSpacing;
}

/* Lines beside the figure keep a gap from it; the next line returns to the
 * margin. */
- (NSArray<NSBezierPath *> *)exclusionForFigure {
	CGFloat side = [self figureSide];
	return @[[NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, side + kParagraphFigureGap, side + _lineSpacing / 2)]];
}

- (void)rebuild {
	/* NSTextView's initializer applies its own font and colour first. */
	if (!_ready || !_bodyFont) return;
	[self.textStorage setAttributedString:[self bodyString]];
	if (_figureView) {
		CGFloat side = [self figureSide];
		_figureView.frame = NSMakeRect(0, 0, side, side);
		self.textContainer.exclusionPaths = [self exclusionForFigure];
	} else {
		self.textContainer.exclusionPaths = @[];
	}
	[self applyLinks];
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
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:[self bodyString]];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(unbounded ? CGFLOAT_MAX : width, CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	if (_figureView) container.exclusionPaths = [self exclusionForFigure];
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	[manager ensureLayoutForTextContainer:container];
	NSRect used = [manager usedRectForTextContainer:container];
	/* A short paragraph still reserves the lines of its figure. */
	CGFloat height = [self revealedBottomInManager:manager container:container];
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
