#pragma mark - Paragraph (long-form text)

/* Long-form prose, set as a book sets it: selectable text with explicit
 * leading, optional hyphenation, and a dropped initial that the following
 * lines wrap around. NSTextField cannot flow text around a shape, so this is a
 * non-editable NSTextView on TextKit 1, whose NSTextContainer.exclusionPaths
 * carve the initial's box out of the first lines — the mechanism Pages uses
 * for floating objects. The initial is drawn by its own view, framed around
 * the glyph's ink, so swashes are never clipped and it can use its own face
 * and colour without changing the story's text. */
@interface LuaDropCapView : NSView
@property(nonatomic, copy) NSString *letter;
@property(nonatomic, strong) NSFont *font;
@property(nonatomic, strong) NSColor *color;
/* Where the glyph's origin and baseline fall inside this view. */
@property(nonatomic) NSPoint baselineOrigin;
@end

@implementation LuaDropCapView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)rect {
	if (!self.letter || !self.font) return;
	[self.letter drawAtPoint:NSMakePoint(self.baselineOrigin.x, self.baselineOrigin.y - self.font.ascender)
		withAttributes:@{NSFontAttributeName: self.font, NSForegroundColorAttributeName: self.color ?: NSColor.controlAccentColor}];
}
@end

@interface LuaParagraphView : NSTextView <NSTextViewDelegate, LuaParagraphLinking>
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSFont *bodyFont;
@property(nonatomic, strong) NSColor *bodyColor;
@property(nonatomic) NSInteger textAlignment;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) BOOL hyphenation;
@property(nonatomic) BOOL dropCap;
@property(nonatomic) NSInteger dropCapLines;
@property(nonatomic, strong) NSFont *dropCapFont;
@property(nonatomic, strong) NSColor *dropCapColor;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
/* The dashed rule under a link; the words keep the body's colour. */
@property(nonatomic, strong) NSColor *linkColor;
/* Characters shown so far, counted as Lua's utf8.len counts them; -1 shows
 * the whole paragraph. See `paragraph_revealed_length`. */
@property(nonatomic) NSInteger revealedCharacters;
/* The revealed height last reported to layout. */
@property(nonatomic) CGFloat revealedBottom;
@property(nonatomic, strong) LuaDropCapView *initialView;
/* The initial's ink in paragraph coordinates; lines wrap around it. */
@property(nonatomic) NSRect initialInk;
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
	_dropCapLines = kParagraphDropCapLines;
	_dropCapColor = NSColor.controlAccentColor;
	_links = @[];
	_revealedCharacters = -1;
	/* The text view reports clicks on links to its delegate; the paragraph
	 * rules them itself, so a link changes only the pointer. */
	self.delegate = self;
	self.linkTextAttributes = @{NSCursorAttributeName: NSCursor.pointingHandCursor};
	_initialView = [[LuaDropCapView alloc] initWithFrame:NSZeroRect];
	_initialView.hidden = YES;
	[_initialView setAccessibilityElement:NO];
	[self addSubview:_initialView];
	[self rebuild];
	return self;
}

- (void)setText:(NSString *)text { _text = [text copy] ?: @""; [self rebuild]; }
- (void)setBodyFont:(NSFont *)font { _bodyFont = font ?: _bodyFont; [self rebuild]; }
- (void)setBodyColor:(NSColor *)color { _bodyColor = color ?: NSColor.labelColor; [self rebuild]; }
- (void)setTextAlignment:(NSInteger)alignment { _textAlignment = alignment; [self rebuild]; }
- (void)setLineSpacing:(CGFloat)value { _lineSpacing = MAX(0, value); [self rebuild]; }
- (void)setHyphenation:(BOOL)value { _hyphenation = value; [self rebuild]; }
- (void)setDropCap:(BOOL)value { _dropCap = value; [self rebuild]; }
- (void)setDropCapLines:(NSInteger)value { _dropCapLines = MAX(2, value); [self rebuild]; }
- (void)setDropCapFont:(NSFont *)font { _dropCapFont = font; [self rebuild]; }
- (void)setDropCapColor:(NSColor *)color { _dropCapColor = color ?: NSColor.controlAccentColor; [self rebuild]; }
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
- (void)setFont:(NSFont *)font { if (font && _initialView) self.bodyFont = font; else [super setFont:font]; }
- (NSColor *)textColor { return _bodyColor; }
- (void)setTextColor:(NSColor *)color { if (_initialView) self.bodyColor = color; else [super setTextColor:color]; }

/* A letter is dropped only when the paragraph starts with one; quotes and
 * digits stay in the running text, as in print. */
- (NSString *)initialLetter {
	if (!_dropCap || _text.length < 2) return nil;
	NSString *letter = [_text substringWithRange:[_text rangeOfComposedCharacterSequenceAtIndex:0]];
	if (![NSCharacterSet.letterCharacterSet characterIsMember:[letter characterAtIndex:0]]) return nil;
	return letter;
}

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

/* Revealed characters of the body, which excludes a dropped initial. */
- (NSUInteger)revealedBodyLength {
	NSUInteger revealed = paragraph_revealed_length(_text, _revealedCharacters);
	NSUInteger initial = [self initialLetter].length;
	return revealed > initial ? revealed - initial : 0;
}

- (NSRange)bodyRangeOfLink:(LuaParagraphLink *)link {
	NSUInteger start = paragraph_revealed_length(_text, MAX(0, link.location));
	NSUInteger end = paragraph_revealed_length(_text, MAX(0, link.location) + MAX(0, link.length));
	NSUInteger initial = [self initialLetter].length;
	start = MAX(start, initial) - initial;
	end = MAX(end, initial) - initial;
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
			value:@(NSUnderlineStyleSingle | NSUnderlineStylePatternDash) range:range];
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
	_initialView.hidden = !([self initialLetter] && _revealedCharacters != 0);
	self.needsDisplay = YES;
}

/* The bottom of the last revealed line; the whole text's height once the
 * reveal reaches the last line, so a finished reveal measures as unrevealed
 * text does. A revealed initial still reserves its lines. */
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
	if ([self initialLetter]) bottom = MAX(bottom, MAX(MAX(2, _dropCapLines) * ([self bodyLineHeight] + _lineSpacing) - _lineSpacing,
		NSMaxY(_initialInk)));
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
	/* Fixed line heights keep the lines beside the initial on the same
	 * pitch the initial was sized for. */
	style.minimumLineHeight = style.maximumLineHeight = [self bodyLineHeight];
	NSString *initial = [self initialLetter];
	NSString *body = initial ? [_text substringFromIndex:initial.length] : _text;
	return [[NSAttributedString alloc] initWithString:body attributes:@{
		NSFontAttributeName: _bodyFont,
		NSForegroundColorAttributeName: _bodyColor,
		NSParagraphStyleAttributeName: style,
	}];
}

/* The initial’s ink, relative to its baseline with y growing upward. */
static NSRect paragraph_ink_bounds(NSFont *font, NSString *letter) {
	unichar characters[2] = {0};
	CGGlyph glyphs[2] = {0};
	NSUInteger count = MIN(letter.length, (NSUInteger)2);
	[letter getCharacters:characters range:NSMakeRange(0, count)];
	CTFontRef ctFont = (__bridge CTFontRef)font;
	if (!CTFontGetGlyphsForCharacters(ctFont, characters, glyphs, (CFIndex)count))
		return NSMakeRect(0, 0, [letter sizeWithAttributes:@{NSFontAttributeName: font}].width, font.capHeight);
	return CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationDefault, glyphs, NULL, 1);
}

/* The dropped initial occupies exactly `dropCapLines` lines, measured by its
 * ink rather than font metrics: script capitals such as Snell Roundhand’s Y
 * swash far below their baseline. A plain capital runs from the first line’s
 * cap height to the last line’s baseline, as in print; one that descends fits
 * its whole ink between that cap height and the last line’s bottom. */
- (void)layoutInitial:(NSString *)letter {
	CGFloat lines = MAX(2, _dropCapLines);
	CGFloat pitch = [self bodyLineHeight] + _lineSpacing;
	/* Fixed-height lines place each baseline at the line's descender. */
	CGFloat firstBaseline = [self bodyLineHeight] + _bodyFont.descender;
	CGFloat capTop = firstBaseline - _bodyFont.capHeight;
	CGFloat lastBaseline = firstBaseline + (lines - 1) * pitch;
	CGFloat lastBottom = lastBaseline - _bodyFont.descender;
	NSFont *base = _dropCapFont ?: [[NSFontManager sharedFontManager] convertFont:_bodyFont toHaveTrait:NSBoldFontMask];
	CGFloat reference = kParagraphDropCapReferenceSize;
	NSFont *measure = [NSFont fontWithDescriptor:base.fontDescriptor size:reference] ?: base;
	NSRect ink = paragraph_ink_bounds(measure, letter);
	BOOL descends = NSMinY(ink) < -kParagraphDropCapDescentFraction * reference;
	CGFloat scale = NSMaxY(ink) > 0 ? (lastBaseline - capTop) / NSMaxY(ink) : 1;
	/* A capital whose foot overshoots the baseline further than the last
	 * line's descent (Chalkduster's A) is fitted whole, like a descender,
	 * so its ink never reaches into a following line. */
	if ((descends || -NSMinY(ink) * scale > lastBottom - lastBaseline) && NSHeight(ink) > 0)
		scale = (lastBottom - capTop) / NSHeight(ink);
	NSFont *font = [NSFont fontWithDescriptor:base.fontDescriptor size:MAX(1, reference * scale)] ?: base;
	NSRect scaled = NSMakeRect(NSMinX(ink) * scale, NSMinY(ink) * scale, NSWidth(ink) * scale, NSHeight(ink) * scale);
	CGFloat baseline = capTop + NSMaxY(scaled);
	/* A swash reaching left of the glyph origin stays inside the margin. */
	CGFloat originX = MAX(0, -NSMinX(scaled));
	NSRect inkRect = NSMakeRect(originX + NSMinX(scaled), baseline - NSMaxY(scaled), NSWidth(scaled), NSHeight(scaled));
	NSRect frame = NSIntegralRect(NSInsetRect(inkRect, -kParagraphDropCapInkOutset, -kParagraphDropCapInkOutset));
	_initialView.letter = letter;
	_initialView.font = font;
	_initialView.color = _dropCapColor;
	_initialView.frame = frame;
	_initialView.baselineOrigin = NSMakePoint(originX - frame.origin.x, baseline - frame.origin.y);
	_initialView.needsDisplay = YES;
	_initialView.hidden = NO;
	_initialInk = inkRect;
}

/* Exactly `dropCapLines` whole lines stay beside the initial, whose ink is
 * fitted inside them, so the next line returns to the margin. */
- (NSArray<NSBezierPath *> *)exclusionForInitial {
	CGFloat pitch = [self bodyLineHeight] + _lineSpacing;
	CGFloat lines = MAX(2, _dropCapLines);
	return @[[NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, NSMaxX(_initialInk) + kParagraphDropCapGap,
		lines * pitch - _lineSpacing / 2)]];
}

- (void)rebuild {
	/* NSTextView's initializer applies its own font and colour first. */
	if (!_initialView || !_bodyFont) return;
	NSString *letter = [self initialLetter];
	[self.textStorage setAttributedString:[self bodyString]];
	if (letter) {
		[self layoutInitial:letter];
		self.textContainer.exclusionPaths = [self exclusionForInitial];
	} else {
		_initialView.hidden = YES;
		_initialInk = NSZeroRect;
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
	NSString *letter = [self initialLetter];
	BOOL unbounded = width <= 0 || width >= CGFLOAT_MAX / 2;
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:[self bodyString]];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(unbounded ? CGFLOAT_MAX : width, CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	if (letter) container.exclusionPaths = [self exclusionForInitial];
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	[manager ensureLayoutForTextContainer:container];
	NSRect used = [manager usedRectForTextContainer:container];
	/* A short paragraph still reserves the lines and ink of its initial. */
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
