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

@interface LuaParagraphView : UITextView
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
	CGFloat inkHeight = descends ? CGRectGetHeight(ink) : CGRectGetMaxY(ink);
	CGFloat scale = inkHeight > 0 ? ((descends ? lastBottom : lastBaseline) - capTop) / inkHeight : 1;
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

/* Whole lines stay beside the initial, so the next line returns to the margin. */
- (NSArray<UIBezierPath *> *)exclusionForInitial {
	CGFloat pitch = _bodyFont.lineHeight + _lineSpacing;
	CGFloat lines = MAX(MAX(2, _dropCapLines), ceil((CGRectGetMaxY(_initialInk) + _lineSpacing) / pitch));
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
	CGFloat height = CGRectGetMaxY(used);
	if (letter) height = MAX(height, MAX(MAX(2, _dropCapLines) * (_bodyFont.lineHeight + _lineSpacing) - _lineSpacing,
		CGRectGetMaxY(_initialInk)));
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
