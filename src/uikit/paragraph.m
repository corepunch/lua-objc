#pragma mark - Paragraph (long-form text)

/* Long-form prose, set as a book sets it: selectable text with explicit
 * leading, optional hyphenation, and a dropped initial that the following
 * lines wrap around. UILabel cannot flow text around a shape, so this is a
 * non-scrolling UITextView on TextKit 1, whose NSTextContainer.exclusionPaths
 * carve the initial's box out of the first lines — the same mechanism Pages
 * and Books use for floating objects. The initial is drawn by its own view,
 * framed around the glyph's ink, so swashes are never clipped and it can use
 * its own face and colour without changing the story's text. */
@interface LuaDropCapView : UIView
@property(nonatomic, copy) NSString *letter;
@property(nonatomic, strong) UIFont *font;
@property(nonatomic, strong) UIColor *color;
/* Where the glyph's origin and baseline fall inside this view. */
@property(nonatomic) CGPoint baselineOrigin;
@end

@implementation LuaDropCapView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	self.opaque = NO;
	self.backgroundColor = UIColor.clearColor;
	self.contentMode = UIViewContentModeRedraw;
	self.userInteractionEnabled = NO;
	self.isAccessibilityElement = NO;
	return self;
}
- (void)drawRect:(CGRect)rect {
	if (!self.letter || !self.font) return;
	[self.letter drawAtPoint:CGPointMake(self.baselineOrigin.x, self.baselineOrigin.y - self.font.ascender)
		withAttributes:@{NSFontAttributeName: self.font, NSForegroundColorAttributeName: self.color ?: UIColor.tintColor}];
}
@end

@interface LuaParagraphView : UITextView <UITextViewDelegate, LuaParagraphLinking>
@property(nonatomic, copy) NSString *paragraphText;
@property(nonatomic, strong) UIFont *bodyFont;
@property(nonatomic, strong) UIColor *bodyColor;
@property(nonatomic) NSTextAlignment bodyAlignment;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) BOOL hyphenation;
@property(nonatomic) BOOL dropCap;
@property(nonatomic) NSInteger dropCapLines;
@property(nonatomic, strong) UIFont *dropCapFont;
@property(nonatomic, strong) UIColor *dropCapColor;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
/* The dashed rule under a link; the words keep the body's colour. */
@property(nonatomic, strong) UIColor *linkColor;
/* Characters shown so far, counted as Lua's utf8.len counts them; -1 shows
 * the whole paragraph. See `paragraph_revealed_length`. */
@property(nonatomic) NSInteger revealedCharacters;
/* The revealed height last reported to layout. */
@property(nonatomic) CGFloat revealedBottom;
@property(nonatomic, strong) LuaDropCapView *initialView;
/* The initial's ink in paragraph coordinates; lines wrap around it. */
@property(nonatomic) CGRect initialInk;
@end

@implementation LuaParagraphView

- (instancetype)init {
	NSTextStorage *storage = [[NSTextStorage alloc] init];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(0, CGFLOAT_MAX)];
	container.widthTracksTextView = YES;
	container.lineFragmentPadding = 0;
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	self = [super initWithFrame:CGRectZero textContainer:container];
	if (!self) return nil;
	self.editable = NO;
	self.selectable = YES;
	self.scrollEnabled = NO;
	self.backgroundColor = UIColor.clearColor;
	self.textContainerInset = UIEdgeInsetsZero;
	_paragraphText = @"";
	_bodyFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_bodyColor = UIColor.labelColor;
	_bodyAlignment = NSTextAlignmentNatural;
	_dropCapLines = kParagraphDropCapLines;
	_dropCapColor = UIColor.tintColor;
	_links = @[];
	_revealedCharacters = -1;
	/* Links are tagged text items, not URLs: the text view reports taps
	 * on them to its delegate and styles nothing itself. */
	self.delegate = self;
	self.linkTextAttributes = @{};
	_initialView = [[LuaDropCapView alloc] initWithFrame:CGRectZero];
	_initialView.hidden = YES;
	[self addSubview:_initialView];
	[self rebuild];
	return self;
}

/* Lua reads and writes `text`; the dropped letter is presentation only. */
- (NSString *)text { return _paragraphText; }
- (void)setText:(NSString *)text { self.paragraphText = text ?: @""; }
- (void)setParagraphText:(NSString *)text { _paragraphText = [text copy] ?: @""; [self rebuild]; }
- (void)setBodyFont:(UIFont *)font { _bodyFont = font ?: _bodyFont; [self rebuild]; }
- (void)setBodyColor:(UIColor *)color { _bodyColor = color ?: UIColor.labelColor; [self rebuild]; }
- (void)setBodyAlignment:(NSTextAlignment)alignment { _bodyAlignment = alignment; [self rebuild]; }
- (void)setLineSpacing:(CGFloat)value { _lineSpacing = MAX(0, value); [self rebuild]; }
- (void)setHyphenation:(BOOL)value { _hyphenation = value; [self rebuild]; }
- (void)setDropCap:(BOOL)value { _dropCap = value; [self rebuild]; }
- (void)setDropCapLines:(NSInteger)value { _dropCapLines = MAX(2, value); [self rebuild]; }
- (void)setDropCapFont:(UIFont *)font { _dropCapFont = font; [self rebuild]; }
- (void)setDropCapColor:(UIColor *)color { _dropCapColor = color ?: UIColor.tintColor; [self rebuild]; }
- (void)setLinks:(NSArray<LuaParagraphLink *> *)links { _links = [links copy] ?: @[]; [self rebuild]; }
- (void)setLinkColor:(UIColor *)color { _linkColor = color; [self applyReveal]; }
- (void)tintColorDidChange { [super tintColorDidChange]; [self applyReveal]; }

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
		uikit_invalidate_layout(self);
	}
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
	NSUInteger revealed = paragraph_revealed_length(_paragraphText, _revealedCharacters);
	NSUInteger initial = [self initialLetter].length;
	return revealed > initial ? revealed - initial : 0;
}

/* A link's range in the text storage, which leaves out a dropped initial. */
- (NSRange)bodyRangeOfLink:(LuaParagraphLink *)link {
	NSUInteger start = paragraph_revealed_length(_paragraphText, MAX(0, link.location));
	NSUInteger end = paragraph_revealed_length(_paragraphText, MAX(0, link.location) + MAX(0, link.length));
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
		[storage addAttribute:UITextItemTagAttributeName value:@(index).stringValue range:range];
		[storage addAttribute:NSUnderlineStyleAttributeName
			value:@(NSUnderlineStyleSingle | NSUnderlineStylePatternDash) range:range];
	}];
	[storage endEditing];
}

/* The link, if any, whose revealed words include the storage's character. */
- (LuaParagraphLink *)linkAtCharacterIndex:(NSUInteger)index {
	if (index >= MIN([self revealedBodyLength], self.textStorage.length)) return nil;
	for (LuaParagraphLink *link in _links)
		if (NSLocationInRange(index, [self bodyRangeOfLink:link])) return link;
	return nil;
}

- (UIMenu *)menuForLink:(LuaParagraphLink *)link {
	NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];
	[link.titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
		NSString *symbol = index < link.symbols.count ? link.symbols[index] : @"";
		UIAction *action = [UIAction actionWithTitle:title
			image:(symbol.length ? [UIImage systemImageNamed:symbol] : nil) identifier:nil
			handler:^(__unused UIAction *selected) { [link performItem:index]; }];
		if (![link.callbacks[index] isKindOfClass:LuaReg.class]) action.attributes = UIMenuElementAttributesDisabled;
		[elements addObject:action];
	}];
	return [UIMenu menuWithTitle:@"" children:elements];
}

/* A link has no primary action, so a tap presents its menu. */
- (UIAction *)textView:(__unused UITextView *)textView primaryActionForTextItem:(__unused UITextItem *)textItem
		defaultAction:(__unused UIAction *)defaultAction {
	return nil;
}

- (UITextItemMenuConfiguration *)textView:(__unused UITextView *)textView
		menuConfigurationForTextItem:(UITextItem *)textItem defaultMenu:(__unused UIMenu *)defaultMenu {
	if (textItem.contentType != UITextItemContentTypeTag) return nil;
	LuaParagraphLink *link = [self linkAtCharacterIndex:textItem.range.location];
	if (!link || link.titles.count == 0) return nil;
	return [UITextItemMenuConfiguration configurationWithMenu:[self menuForLink:link]];
}

- (void)applyReveal {
	NSTextStorage *storage = self.textStorage;
	NSUInteger shown = MIN([self revealedBodyLength], storage.length);
	[storage beginEditing];
	[storage addAttribute:NSForegroundColorAttributeName value:_bodyColor range:NSMakeRange(0, shown)];
	[storage addAttribute:NSForegroundColorAttributeName value:UIColor.clearColor
		range:NSMakeRange(shown, storage.length - shown)];
	/* A link is ruled only under the words typed so far. */
	for (LuaParagraphLink *link in _links) {
		NSRange range = [self bodyRangeOfLink:link];
		if (range.location == NSNotFound) continue;
		NSRange visible = NSIntersectionRange(range, NSMakeRange(0, shown));
		[storage addAttribute:NSUnderlineColorAttributeName value:UIColor.clearColor range:range];
		if (visible.length) [storage addAttribute:NSUnderlineColorAttributeName
			value:_linkColor ?: self.tintColor range:visible];
	}
	[storage endEditing];
	_initialView.hidden = !([self initialLetter] && _revealedCharacters != 0);
}

/* The bottom of the last revealed line; the whole text's height once the
 * reveal reaches the last line, so a finished reveal measures as unrevealed
 * text does. A revealed initial still reserves its lines. */
- (CGFloat)revealedBottomInManager:(NSLayoutManager *)manager container:(NSTextContainer *)container {
	if (_revealedCharacters == 0 || _paragraphText.length == 0) return 0;
	[manager ensureLayoutForTextContainer:container];
	CGFloat bottom = CGRectGetMaxY([manager usedRectForTextContainer:container]);
	NSUInteger body = [self revealedBodyLength];
	if (_revealedCharacters > 0 && body < manager.textStorage.length) {
		if (body == 0) bottom = 0;
		else {
			NSRange line;
			CGRect used = [manager lineFragmentUsedRectForGlyphAtIndex:
				[manager glyphIndexForCharacterAtIndex:body - 1] effectiveRange:&line];
			if (NSMaxRange(line) < manager.numberOfGlyphs) bottom = CGRectGetMaxY(used);
		}
	}
	if ([self initialLetter]) bottom = MAX(bottom, MAX(MAX(2, _dropCapLines) * (_bodyFont.lineHeight + _lineSpacing) - _lineSpacing,
		CGRectGetMaxY(_initialInk)));
	return bottom;
}

/* A letter is dropped only when the paragraph starts with one; quotes and
 * digits stay in the running text, as in print. */
- (NSString *)initialLetter {
	if (!_dropCap || _paragraphText.length < 2) return nil;
	NSRange first = [_paragraphText rangeOfComposedCharacterSequenceAtIndex:0];
	NSString *letter = [_paragraphText substringWithRange:first];
	unichar c = [letter characterAtIndex:0];
	if (![NSCharacterSet.letterCharacterSet characterIsMember:c]) return nil;
	return letter;
}

- (NSAttributedString *)bodyStringWithoutInitial:(BOOL)withoutInitial {
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.lineSpacing = _lineSpacing;
	style.alignment = _bodyAlignment;
	style.hyphenationFactor = _hyphenation ? 1.0 : 0.0;
	NSString *body = _paragraphText;
	NSString *initial = withoutInitial ? [self initialLetter] : nil;
	if (initial) body = [body substringFromIndex:initial.length];
	return [[NSAttributedString alloc] initWithString:body attributes:@{
		NSFontAttributeName: _bodyFont,
		NSForegroundColorAttributeName: _bodyColor,
		NSParagraphStyleAttributeName: style,
	}];
}

/* The initial’s ink, relative to its baseline with y growing upward. */
static CGRect paragraph_ink_bounds(UIFont *font, NSString *letter) {
	unichar characters[2] = {0};
	CGGlyph glyphs[2] = {0};
	NSUInteger count = MIN(letter.length, (NSUInteger)2);
	[letter getCharacters:characters range:NSMakeRange(0, count)];
	CTFontRef ctFont = (__bridge CTFontRef)font;
	if (!CTFontGetGlyphsForCharacters(ctFont, characters, glyphs, (CFIndex)count))
		return CGRectMake(0, 0, [letter sizeWithAttributes:@{NSFontAttributeName: font}].width, font.capHeight);
	return CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationDefault, glyphs, NULL, 1);
}

/* The dropped initial occupies exactly `dropCapLines` lines, measured by its
 * ink rather than font metrics: script capitals such as Snell Roundhand’s Y
 * swash far below their baseline. A plain capital runs from the first line’s
 * cap height to the last line’s baseline, as in print; one that descends fits
 * its whole ink between that cap height and the last line’s descender. */
- (void)layoutInitial:(NSString *)letter {
	CGFloat lines = MAX(2, _dropCapLines);
	CGFloat pitch = _bodyFont.lineHeight + _lineSpacing;
	CGFloat capTop = _bodyFont.ascender - _bodyFont.capHeight;
	CGFloat lastBaseline = _bodyFont.ascender + (lines - 1) * pitch;
	CGFloat lastBottom = lastBaseline - _bodyFont.descender;
	UIFont *base = _dropCapFont ?: [UIFont fontWithDescriptor:
		[_bodyFont.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] ?: _bodyFont.fontDescriptor
		size:_bodyFont.pointSize];
	CGFloat reference = kParagraphDropCapReferenceSize;
	CGRect ink = paragraph_ink_bounds([base fontWithSize:reference], letter);
	BOOL descends = CGRectGetMinY(ink) < -kParagraphDropCapDescentFraction * reference;
	CGFloat scale = CGRectGetMaxY(ink) > 0 ? (lastBaseline - capTop) / CGRectGetMaxY(ink) : 1;
	/* A capital whose foot overshoots the baseline further than the last
	 * line's descent (Chalkduster's A) is fitted whole, like a descender,
	 * so its ink never reaches into a following line. */
	if ((descends || -CGRectGetMinY(ink) * scale > lastBottom - lastBaseline) && CGRectGetHeight(ink) > 0)
		scale = (lastBottom - capTop) / CGRectGetHeight(ink);
	UIFont *font = [base fontWithSize:MAX(1, reference * scale)];
	CGRect scaled = CGRectMake(CGRectGetMinX(ink) * scale, CGRectGetMinY(ink) * scale,
		CGRectGetWidth(ink) * scale, CGRectGetHeight(ink) * scale);
	CGFloat baseline = capTop + CGRectGetMaxY(scaled);
	/* A swash reaching left of the glyph origin stays inside the margin. */
	CGFloat originX = MAX(0, -CGRectGetMinX(scaled));
	CGRect inkRect = CGRectMake(originX + CGRectGetMinX(scaled), baseline - CGRectGetMaxY(scaled),
		CGRectGetWidth(scaled), CGRectGetHeight(scaled));
	CGFloat outset = kParagraphDropCapInkOutset;
	CGRect frame = CGRectIntegral(CGRectInset(inkRect, -outset, -outset));
	_initialView.letter = letter;
	_initialView.font = font;
	_initialView.color = _dropCapColor;
	_initialView.frame = frame;
	_initialView.baselineOrigin = CGPointMake(originX - frame.origin.x, baseline - frame.origin.y);
	[_initialView setNeedsDisplay];
	_initialView.hidden = NO;
	_initialInk = inkRect;
}

/* Exactly `dropCapLines` whole lines stay beside the initial, whose ink is
 * fitted inside them, so the next line returns to the margin. */
- (NSArray<UIBezierPath *> *)exclusionForInitial {
	CGFloat pitch = _bodyFont.lineHeight + _lineSpacing;
	CGFloat lines = MAX(2, _dropCapLines);
	return @[[UIBezierPath bezierPathWithRect:CGRectMake(0, 0,
		CGRectGetMaxX(_initialInk) + kParagraphDropCapGap, lines * pitch - _lineSpacing / 2)]];
}

- (void)rebuild {
	/* UITextView's initializer applies its own font and colour before this
	 * class has finished initializing. */
	if (!_initialView || !_bodyFont) return;
	NSString *letter = [self initialLetter];
	[self.textStorage setAttributedString:[self bodyStringWithoutInitial:YES]];
	if (letter) {
		[self layoutInitial:letter];
		self.textContainer.exclusionPaths = [self exclusionForInitial];
	} else {
		_initialView.hidden = YES;
		_initialInk = CGRectZero;
		self.textContainer.exclusionPaths = @[];
	}
	[self applyLinks];
	[self applyReveal];
	self.accessibilityValue = _paragraphText;
	[self invalidateIntrinsicContentSize];
	[self setNeedsLayout];
}

/* Measurement uses a private TextKit stack so proposing a width never moves
 * the live container. Unbounded proposals return the unwrapped line. */
- (CGSize)sizeThatFits:(CGSize)proposal {
	/* Empty text takes no space, as SwiftUI Text(""). */
	if (_paragraphText.length == 0) return CGSizeZero;
	NSString *letter = [self initialLetter];
	CGFloat width = proposal.width;
	BOOL unbounded = width <= 0 || width >= CGFLOAT_MAX / 2;
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:[self bodyStringWithoutInitial:YES]];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(unbounded ? CGFLOAT_MAX : width, CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	if (letter) container.exclusionPaths = [self exclusionForInitial];
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	[manager ensureLayoutForTextContainer:container];
	CGRect used = [manager usedRectForTextContainer:container];
	CGFloat scale = self.traitCollection.displayScale ?: 1;
	/* A short paragraph still reserves the lines and ink of its initial. */
	CGFloat height = [self revealedBottomInManager:manager container:container];
	CGFloat resultWidth = unbounded ? CGRectGetMaxX(used) : width;
	return CGSizeMake(ceil(resultWidth * scale) / scale, ceil(height * scale) / scale);
}

/* The layout engine proposes a width and reads the height from
 * sizeThatFits:, as SwiftUI does for Text; there is no intrinsic size. */
- (CGSize)intrinsicContentSize {
	return CGSizeMake(UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric);
}

- (NSTextAlignment)textAlignment { return _bodyAlignment; }
- (void)setTextAlignment:(NSTextAlignment)alignment { self.bodyAlignment = alignment; }
- (UIFont *)font { return _bodyFont; }
- (void)setFont:(UIFont *)font { if (font) self.bodyFont = font; }
- (UIColor *)textColor { return _bodyColor; }
- (void)setTextColor:(UIColor *)color { self.bodyColor = color; }
@end

static int bridge_UIKitControls_paragraph(lua_State *L) {
	LuaParagraphView *view = [[LuaParagraphView alloc] init];
	view.text = @(luaL_optstring(L, 1, ""));
	push_objc(L, view, "uiview");
	return 1;
}

