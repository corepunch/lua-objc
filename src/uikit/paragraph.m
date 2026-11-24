#pragma mark - Paragraph (long-form text)

/* Native selectable prose with explicit leading and optional hyphenation. */
@interface LuaParagraphView : UITextView <UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate, LuaParagraphText>
- (void)presentActionMenuAtLocation:(NSUInteger)location;
@property(nonatomic, strong) UIEditMenuInteraction *actionMenu;
@property(nonatomic, copy) NSString *paragraphText;
@property(nonatomic, strong) UIFont *bodyFont;
@property(nonatomic, strong) UIColor *bodyColor;
@property(nonatomic) NSTextAlignment bodyAlignment;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) BOOL hyphenation;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
@property(nonatomic, copy) NSArray<NSDictionary *> *boldRanges;
@property(nonatomic, copy) NSArray<NSDictionary *> *italicRanges;
/* The colour of a link's words. */
@property(nonatomic, strong) UIColor *linkColor;
@property(nonatomic) NSInteger revealedCharacters;
/* Set once the view is initialized; see -rebuild. */
@property(nonatomic) BOOL ready;
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
	_links = @[];
	_revealedCharacters = -1;
	/* Linked runs stay ordinary text for native long-press selection.
	 * Only a short tap is intercepted; text-item tags would route long
	 * presses into UIKit's link interaction instead of selection. */
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedWord:)];
	tap.cancelsTouchesInView = NO;
	tap.delegate = self;
	[self addGestureRecognizer:tap];
	_actionMenu = [[UIEditMenuInteraction alloc] initWithDelegate:self];
	[self addInteraction:_actionMenu];
	self.linkTextAttributes = @{};
	_ready = YES;
	[self rebuild];
	return self;
}

/* Lua reads and writes `text`. */
- (NSString *)text { return _paragraphText; }
- (void)setText:(NSString *)text { self.paragraphText = text ?: @""; }
- (void)setParagraphText:(NSString *)text { _paragraphText = [text copy] ?: @""; [self rebuild]; }
- (void)setBodyFont:(UIFont *)font { _bodyFont = font ?: _bodyFont; [self rebuild]; }
- (void)setBodyColor:(UIColor *)color { _bodyColor = color ?: UIColor.labelColor; [self rebuild]; }
- (void)setBodyAlignment:(NSTextAlignment)alignment { _bodyAlignment = alignment; [self rebuild]; }
- (void)setLineSpacing:(CGFloat)value { _lineSpacing = MAX(0, value); [self rebuild]; }
- (void)setHyphenation:(BOOL)value { _hyphenation = value; [self rebuild]; }
- (void)setLinks:(NSArray<LuaParagraphLink *> *)links { _links = [links copy] ?: @[]; [self rebuild]; }
- (void)setBoldRanges:(NSArray<NSDictionary *> *)ranges { _boldRanges = [ranges copy] ?: @[]; [self rebuild]; }
- (void)setItalicRanges:(NSArray<NSDictionary *> *)ranges { _italicRanges = [ranges copy] ?: @[]; [self rebuild]; }
- (void)setLinkColor:(UIColor *)color { _linkColor = color; [self applyReveal]; }
- (id)paragraphLinkColor { return _linkColor ?: self.tintColor; }
- (void)tintColorDidChange { [super tintColorDidChange]; [self applyReveal]; }

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
	/* Edit menus display submenus as another horizontal page. Keep the
	 * first three verbs together; UIKit owns the page arrow and bar metrics. */
	if (elements.count > kParagraphMenuPageActions) {
		NSArray *remaining = [elements subarrayWithRange:NSMakeRange(kParagraphMenuPageActions,
			elements.count - kParagraphMenuPageActions)];
		[elements removeObjectsInRange:NSMakeRange(kParagraphMenuPageActions, remaining.count)];
		[elements addObject:[UIMenu menuWithTitle:@"" image:[UIImage systemImageNamed:@"chevron.forward"]
			identifier:nil options:0 children:remaining]];
	}
	return [UIMenu menuWithTitle:@"" children:elements];
}

/* Hit-test laid-out glyphs so empty space beside a link is still ordinary
 * text. Revealed ranges use the same contract as native menu actions. */
- (NSUInteger)linkedCharacterAtPoint:(CGPoint)point {
	point.x -= self.textContainerInset.left;
	point.y -= self.textContainerInset.top;
	CGFloat fraction;
	NSUInteger glyph = [self.layoutManager glyphIndexForPoint:point inTextContainer:self.textContainer
		fractionOfDistanceThroughGlyph:&fraction];
	if (glyph >= self.layoutManager.numberOfGlyphs) return NSNotFound;
	CGRect rect = [self.layoutManager boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:self.textContainer];
	if (!CGRectContainsPoint(rect, point)) return NSNotFound;
	NSUInteger character = [self.layoutManager characterIndexForGlyphAtIndex:glyph];
	LuaParagraphLink *link = paragraph_link_at(self, character);
	return link.titles.count ? character : NSNotFound;
}

- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
	return [self linkedCharacterAtPoint:[touch locationInView:self]] != NSNotFound;
}

- (void)tappedWord:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateRecognized) return;
	NSUInteger location = [self linkedCharacterAtPoint:[tap locationInView:self]];
	if (location != NSNotFound) [self presentActionMenuAtLocation:location];
}

- (void)presentActionMenuAtLocation:(NSUInteger)location {
	if (!paragraph_link_at(self, location).titles.count) return;
	if (!UIAccessibilityIsReduceMotionEnabled())
		uikit_impact_feedback(UIImpactFeedbackStyleLight, kParagraphTapHapticIntensity);
	UIEditMenuConfiguration *configuration = [UIEditMenuConfiguration
		configurationWithIdentifier:@(location) sourcePoint:CGPointZero];
	[self.actionMenu presentEditMenuWithConfiguration:configuration];
}

- (UIMenu *)editMenuInteraction:(__unused UIEditMenuInteraction *)interaction
		menuForConfiguration:(UIEditMenuConfiguration *)configuration
		suggestedActions:(__unused NSArray<UIMenuElement *> *)suggestedActions {
	LuaParagraphLink *link = paragraph_link_at(self, [(NSNumber *)configuration.identifier unsignedIntegerValue]);
	return link ? [self menuForLink:link] : nil;
}

- (CGRect)editMenuInteraction:(__unused UIEditMenuInteraction *)interaction
		targetRectForConfiguration:(UIEditMenuConfiguration *)configuration {
	LuaParagraphLink *link = paragraph_link_at(self, [(NSNumber *)configuration.identifier unsignedIntegerValue]);
	if (!link) return CGRectNull;
	NSRange range = paragraph_link_range(self, link);
	UITextPosition *start = [self positionFromPosition:self.beginningOfDocument offset:range.location];
	UITextPosition *end = [self positionFromPosition:start offset:range.length];
	return [self firstRectForRange:[self textRangeFromPosition:start toPosition:end]];
}

- (void)applyReveal {
	paragraph_apply_reveal(self, _bodyColor, self.paragraphLinkColor, UIColor.clearColor);
}

- (NSAttributedString *)bodyString {
	return paragraph_body_string(_paragraphText, _bodyFont, _bodyColor, _lineSpacing, _bodyAlignment, _hyphenation, 0);
}

- (void)rebuild {
	/* UITextView's initializer applies its own font and colour before this
	 * class has finished initializing. */
	if (!_ready || !_bodyFont) return;
	[self.textStorage setAttributedString:[self bodyString]];
	paragraph_apply_links(self, NO);
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
	CGFloat width = proposal.width;
	BOOL unbounded = width <= 0 || width >= CGFLOAT_MAX / 2;
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:self.textStorage];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(unbounded ? CGFLOAT_MAX : width, CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	[manager ensureLayoutForTextContainer:container];
	CGRect used = [manager usedRectForTextContainer:container];
	CGFloat scale = self.traitCollection.displayScale ?: 1;
	CGFloat height = CGRectGetMaxY(used);
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

/* Simulator regression harness: use the same presentation path as a tap. */
static int bridge_test_paragraph_edit_menu(lua_State *L) {
	LuaParagraphView *view = (LuaParagraphView *)paragraph_check(L, 1);
	lua_Integer index = luaL_checkinteger(L, 2);
	if (index < 1 || index > (lua_Integer)view.links.count) return luaL_error(L, "no such paragraph link");
	NSRange range = paragraph_link_range(view, view.links[(NSUInteger)index - 1]);
	/* Fail the Simulator fixture if link tags or delegate overrides steal
	 * ordinary text selection again. */
	if (view.delegate != nil || !view.selectable || view.editable)
		return luaL_error(L, "paragraph must retain native read-only selection");
	if (range.location != NSNotFound && [view.textStorage attribute:UITextItemTagAttributeName
		atIndex:range.location effectiveRange:NULL])
		return luaL_error(L, "interactive words must remain untagged for native long press");

	if (range.location != NSNotFound && paragraph_link_at(view, range.location))
		[view presentActionMenuAtLocation:range.location];
	return 0;
}
