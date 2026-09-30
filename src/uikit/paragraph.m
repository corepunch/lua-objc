#pragma mark - Paragraph (long-form text)

/* Long-form prose, set as a book sets it: selectable text with explicit
 * leading, optional hyphenation, and a figure the first lines wrap around, as
 * Zork Zero set each room's picture beside its description. UILabel cannot
 * flow text around a shape, so this is a non-scrolling UITextView on TextKit
 * 1, whose NSTextContainer.exclusionPaths carve the figure's square out of the
 * first lines — the same mechanism Pages and Books use for floating objects.
 * The figure is an ordinary view (an image view from Lua) that the paragraph
 * places. */
@interface LuaParagraphLayoutManager : NSLayoutManager
@end

@implementation LuaParagraphLayoutManager
- (void)drawUnderlineForGlyphRange:(NSRange)glyphRange underlineType:(NSUnderlineStyle)underlineVal
		baselineOffset:(CGFloat)baselineOffset lineFragmentRect:(CGRect)lineRect
		lineFragmentGlyphRange:(NSRange)lineGlyphRange containerOrigin:(CGPoint)containerOrigin {
	[super drawUnderlineForGlyphRange:glyphRange underlineType:underlineVal
		baselineOffset:baselineOffset + kParagraphLinkUnderlineOffset lineFragmentRect:lineRect
		lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
}
@end

@interface LuaParagraphView : UITextView <UITextViewDelegate, LuaParagraphLinking>
@property(nonatomic, copy) NSString *paragraphText;
@property(nonatomic, strong) UIFont *bodyFont;
@property(nonatomic, strong) UIColor *bodyColor;
@property(nonatomic) NSTextAlignment bodyAlignment;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) BOOL hyphenation;
/* A view floated at the leading edge, a square `figureLines` lines tall. */
@property(nonatomic, strong) UIView *figureView;
@property(nonatomic) NSInteger figureLines;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
/* The colour of a link's words and the thicker dotted rule under them. */
@property(nonatomic, strong) UIColor *linkColor;
/* Characters shown so far, counted as Lua's utf8.len counts them; -1 shows
 * the whole paragraph. See `paragraph_revealed_length`. */
@property(nonatomic) NSInteger revealedCharacters;
/* The revealed height last reported to layout. */
@property(nonatomic) CGFloat revealedBottom;
/* Set once the view is initialized; see -rebuild. */
@property(nonatomic) BOOL ready;
@end

@implementation LuaParagraphView

- (instancetype)init {
	NSTextStorage *storage = [[NSTextStorage alloc] init];
	NSLayoutManager *manager = [[LuaParagraphLayoutManager alloc] init];
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
	_figureLines = kParagraphFigureLines;
	_links = @[];
	_revealedCharacters = -1;
	/* Links are tagged text items, not URLs: the text view reports taps
	 * on them to its delegate and styles nothing itself. */
	self.delegate = self;
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
- (void)setFigureView:(UIView *)view {
	if (view == _figureView) return;
	[_figureView removeFromSuperview];
	_figureView = view;
	if (view) {
		view.userInteractionEnabled = NO;
		view.clipsToBounds = YES;
		[self addSubview:view];
	}
	[self rebuild];
}
- (void)setFigureLines:(NSInteger)value { _figureLines = MAX(1, value); [self rebuild]; }
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

- (NSUInteger)revealedBodyLength {
	return paragraph_revealed_length(_paragraphText, _revealedCharacters);
}

/* A link's range in the text storage. */
- (NSRange)bodyRangeOfLink:(LuaParagraphLink *)link {
	NSUInteger start = paragraph_revealed_length(_paragraphText, MAX(0, link.location));
	NSUInteger end = paragraph_revealed_length(_paragraphText, MAX(0, link.location) + MAX(0, link.length));
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
			value:@(NSUnderlineStyleThick | NSUnderlineStylePatternDot) range:range];
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
		if (!visible.length) continue;
		UIColor *ink = _linkColor ?: self.tintColor;
		[storage addAttribute:NSForegroundColorAttributeName value:ink range:visible];
		[storage addAttribute:NSUnderlineColorAttributeName value:ink range:visible];
	}
	[storage endEditing];
	_figureView.hidden = _revealedCharacters == 0;
}

/* The bottom of the last revealed line; the whole text's height once the
 * reveal reaches the last line, so a finished reveal measures as unrevealed
 * text does. A revealed figure still reserves its lines. */
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
	if (_figureView) bottom = MAX(bottom, [self figureSide]);
	return bottom;
}

- (NSAttributedString *)bodyString {
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.lineSpacing = _lineSpacing;
	style.alignment = _bodyAlignment;
	style.hyphenationFactor = _hyphenation ? 1.0 : 0.0;
	return [[NSAttributedString alloc] initWithString:_paragraphText attributes:@{
		NSFontAttributeName: _bodyFont,
		NSForegroundColorAttributeName: _bodyColor,
		NSParagraphStyleAttributeName: style,
	}];
}

/* The figure spans exactly `figureLines` lines, from the first line's top to
 * the last line's bottom, and is as wide as it is tall. */
- (CGFloat)figureSide {
	return _figureLines * (_bodyFont.lineHeight + _lineSpacing) - _lineSpacing;
}

/* Lines beside the figure keep a gap from it; the next line returns to the
 * margin. */
- (NSArray<UIBezierPath *> *)exclusionForFigure {
	CGFloat side = [self figureSide];
	return @[[UIBezierPath bezierPathWithRect:CGRectMake(0, 0, side + kParagraphFigureGap, side + _lineSpacing / 2)]];
}

- (void)rebuild {
	/* UITextView's initializer applies its own font and colour before this
	 * class has finished initializing. */
	if (!_ready || !_bodyFont) return;
	[self.textStorage setAttributedString:[self bodyString]];
	if (_figureView) {
		CGFloat side = [self figureSide];
		_figureView.frame = CGRectMake(0, 0, side, side);
		self.textContainer.exclusionPaths = [self exclusionForFigure];
	} else {
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
	CGFloat width = proposal.width;
	BOOL unbounded = width <= 0 || width >= CGFLOAT_MAX / 2;
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:[self bodyString]];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(unbounded ? CGFLOAT_MAX : width, CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	if (_figureView) container.exclusionPaths = [self exclusionForFigure];
	[storage addLayoutManager:manager];
	[manager addTextContainer:container];
	[manager ensureLayoutForTextContainer:container];
	CGRect used = [manager usedRectForTextContainer:container];
	CGFloat scale = self.traitCollection.displayScale ?: 1;
	/* A short paragraph still reserves the lines of its figure. */
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
