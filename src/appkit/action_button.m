#pragma mark - LuaButtonTarget

@interface LuaButtonTarget : NSObject
+ (instancetype)shared;
@end

@implementation LuaButtonTarget

+ (instancetype)shared {
	static LuaButtonTarget *instance = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ instance = [[self alloc] init]; });
	return instance;
}

- (void)onAction:(id)sender {
	id refObj = objc_getAssociatedObject(sender, &kKeys[kCallbackKey]);
	if (!refObj || !gL) return;
	int ref = [refObj intValue];

	lua_rawgeti(gL, LUA_REGISTRYINDEX, ref);
	push_objc(gL, sender, "nsview");
	lua_objc_pcall(gL, 1, 0, "button");
}

@end

#pragma mark - Shared lookup tables

typedef struct {
	NSString *name;
	NSInteger value;
} NameValueEntry;

static NameValueEntry GridLinesMap[] = {
	{@"horizontal", 1},
	{@"vertical",   2},
	{@"both",       3},
	{nil, 0}
};

static NameValueEntry TableStyleMap[] = {
	{@"plain",     NSTableViewStylePlain},
	{@"fullWidth", NSTableViewStyleFullWidth},
	{@"inset",     NSTableViewStyleInset},
	{@"sourceList",NSTableViewStyleSourceList},
	{nil, -1}
};

static NameValueEntry AlignmentMap[] = {
	{@"trailing", NSTextAlignmentRight},
	{@"center",   NSTextAlignmentCenter},
	{nil, NSTextAlignmentLeft}
};

static NSInteger lookupNameValue(NSString *name, NameValueEntry *map, NSInteger defaultVal) {
	if (!name) return defaultVal;
	for (int i = 0; map[i].name; i++) {
		if ([name isEqualToString:map[i].name])
			return map[i].value;
	}
	return defaultVal;
}

static CGFloat lookupFontWeight(NSString *name) {
	if (!name) return NSFontWeightRegular;
	if ([name isEqualToString:@"bold"]) return NSFontWeightBold;
	if ([name isEqualToString:@"semibold"]) return NSFontWeightSemibold;
	if ([name isEqualToString:@"medium"]) return NSFontWeightMedium;
	if ([name isEqualToString:@"light"]) return NSFontWeightLight;
	if ([name isEqualToString:@"heavy"]) return NSFontWeightHeavy;
	return NSFontWeightRegular;
}

typedef struct {
	const char *key;
	void (^apply)(lua_State *L, int idx);
} TablePropParser;

typedef struct {
	const char *name;
	lua_CFunction func;
} MethodEntry;

static lua_CFunction lookupMethod(const char *name, MethodEntry *map) {
	for (int i = 0; map[i].name; i++) {
		if (strcmp(name, map[i].name) == 0)
			return map[i].func;
	}
	return NULL;
}

typedef NS_ENUM(NSInteger, LuaActionButtonStyle) {
	LuaActionButtonStylePlain,
	LuaActionButtonStylePrimary,
	LuaActionButtonStyleRow,
	LuaActionButtonStyleLink,
};

static NameValueEntry ActionButtonStyleMap[] = {
	{@"plain",   LuaActionButtonStylePlain},
	{@"primary", LuaActionButtonStylePrimary},
	{@"row",     LuaActionButtonStyleRow},
	{@"link",    LuaActionButtonStyleLink},
	{nil, LuaActionButtonStylePlain}
};

typedef NS_ENUM(NSInteger, LayoutAxis) {
	LayoutAxisNone = -1,
	LayoutAxisVStack,
	LayoutAxisHStack,
	LayoutAxisHSplit,
	LayoutAxisVSplit,
};

static LayoutAxis layout_axis(NSView *view) {
	NSNumber *val = objc_getAssociatedObject(view, &kKeys[kAxisKey]);
	return val ? (LayoutAxis)val.integerValue : LayoutAxisNone;
}

#pragma mark - Compound action button

static NSColor *semantic_color(NSString *name) {
	if ([name isEqualToString:@"systemGreen"]) return NSColor.systemGreenColor;
	if ([name isEqualToString:@"systemRed"]) return NSColor.systemRedColor;
	if ([name isEqualToString:@"secondary"]) return NSColor.secondaryLabelColor;
	if ([name isEqualToString:@"tertiary"]) return NSColor.tertiaryLabelColor;
	if ([name isEqualToString:@"accent"]) return NSColor.controlAccentColor;
	if ([name isEqualToString:@"white"]) return NSColor.whiteColor;
	if ([name isEqualToString:@"separator"]) return NSColor.separatorColor;
	if ([name isEqualToString:@"background"]) return NSColor.windowBackgroundColor;
	return NSColor.labelColor;
}

@interface LuaActionButton : NSButton
@property (nonatomic, strong) NSBox *backgroundView;
@property (nonatomic, strong) NSImageView *symbolView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic) NSInteger presentationStyle;
@property (nonatomic) BOOL hovering;
@property (nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@end

@implementation LuaActionButton

- (instancetype)initWithTitle:(NSString *)title
					 subtitle:(NSString *)subtitle
					   symbol:(NSString *)symbol
						detail:(NSString *)detail
						 style:(NSString *)style
{
	self = [super initWithFrame:NSZeroRect];
	if (!self) return nil;

	_presentationStyle = lookupNameValue(style ?: @"plain",
		ActionButtonStyleMap, LuaActionButtonStylePlain);
	self.title = @"";
	self.bordered = NO;
	self.focusRingType = NSFocusRingTypeDefault;

	// NSBox resolves dynamic system fill colors in its effective appearance.
	// Keeping it behind the content avoids caching an NSColor as a stale CGColor
	// when a window switches between Aqua and Dark Aqua.
	_backgroundView = [[NSBox alloc] initWithFrame:NSZeroRect];
	_backgroundView.boxType = NSBoxCustom;
	_backgroundView.borderWidth = 0;
	_backgroundView.titlePosition = NSNoTitle;
	_backgroundView.cornerRadius = kActionBtnCornerRadius;
	_backgroundView.contentViewMargins = NSZeroSize;

	_symbolView = [[NSImageView alloc] initWithFrame:NSZeroRect];
	if (symbol.length > 0) {
		NSImageSymbolConfiguration *configuration =
			[NSImageSymbolConfiguration configurationWithPointSize:
				_presentationStyle == LuaActionButtonStyleRow
					? kActionBtnSymbolSizeRow : kActionBtnSymbolSize
												 weight:NSFontWeightMedium];
		NSImage *image = [NSImage imageWithSystemSymbolName:symbol
			accessibilityDescription:title];
		_symbolView.image = [image imageWithSymbolConfiguration:configuration];
		_symbolView.imageScaling = NSImageScaleProportionallyDown;
	}

	_titleLabel = [NSTextField labelWithString:title ?: @""];
	_titleLabel.font = [NSFont systemFontOfSize:kActionBtnTitleFontSize weight:
		_presentationStyle == LuaActionButtonStylePrimary
			? NSFontWeightSemibold : NSFontWeightRegular];
	BOOL wrapsTitle = _presentationStyle != LuaActionButtonStyleRow
		&& _presentationStyle != LuaActionButtonStyleLink;
	_titleLabel.lineBreakMode = wrapsTitle
		? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
	_titleLabel.maximumNumberOfLines = wrapsTitle ? kActionBtnTitleMaxLines : 1;
	_titleLabel.cell.wraps = wrapsTitle;

	_subtitleLabel = [NSTextField labelWithString:subtitle ?: @""];
	_subtitleLabel.font = [NSFont systemFontOfSize:kActionBtnSubtitleFontSize
										   weight:NSFontWeightRegular];
	_subtitleLabel.lineBreakMode = _presentationStyle == LuaActionButtonStyleRow
		? NSLineBreakByTruncatingMiddle : NSLineBreakByTruncatingTail;
	_subtitleLabel.maximumNumberOfLines = 1;

	_detailLabel = [NSTextField labelWithString:detail ?: @""];
	_detailLabel.font = [NSFont systemFontOfSize:kActionBtnDetailFontSize
										 weight:NSFontWeightRegular];
	_detailLabel.alignment = NSTextAlignmentRight;
	_detailLabel.lineBreakMode = NSLineBreakByClipping;

	[self addSubview:_backgroundView];
	[self addSubview:_symbolView];
	[self addSubview:_titleLabel];
	[self addSubview:_subtitleLabel];
	[self addSubview:_detailLabel];
	self.accessibilityLabel = title;
	self.accessibilityHelp = subtitle;
	[self updatePresentation];
	return self;
}

- (NSView *)hitTest:(NSPoint)point {
	return NSPointInRect(point, self.bounds) ? self : nil;
}

- (NSSize)intrinsicContentSize {
	CGFloat height;
	switch (_presentationStyle) {
		case LuaActionButtonStylePrimary: height = kActionBtnHeightPrimary; break;
		case LuaActionButtonStyleRow:     height = kActionBtnHeightRow;     break;
		case LuaActionButtonStyleLink:    height = kActionBtnHeightLink;    break;
		default:                          height = kActionBtnHeightPlain;   break;
	}
	return NSMakeSize(kActionBtnWidth, height);
}

- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	if (_hoverTrackingArea) [self removeTrackingArea:_hoverTrackingArea];
	_hoverTrackingArea = [[NSTrackingArea alloc]
		initWithRect:self.bounds
			options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
			  owner:self
		   userInfo:nil];
	[self addTrackingArea:_hoverTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
	_hovering = YES;
	[self updatePresentation];
}

- (void)mouseExited:(NSEvent *)event {
	_hovering = NO;
	[self updatePresentation];
}

- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self updatePresentation];
}

- (void)updatePresentation {
	BOOL primary = _presentationStyle == LuaActionButtonStylePrimary;
	BOOL link = _presentationStyle == LuaActionButtonStyleLink;
	_backgroundView.cornerRadius = primary || !link ? kActionBtnCornerRadius : 0;

	NSColor *background = NSColor.clearColor;
	if (primary) {
		background = _hovering
			? [NSColor.controlAccentColor colorWithAlphaComponent:kActionBtnHoverPrimary]
			: NSColor.controlAccentColor;
	} else if (_hovering) {
		background = [NSColor.labelColor colorWithAlphaComponent:kActionBtnHoverSecondary];
	}
	_backgroundView.fillColor = background;

	_titleLabel.textColor = primary ? NSColor.whiteColor
		: (link ? NSColor.controlAccentColor : NSColor.labelColor);
	_subtitleLabel.textColor = primary
		? [NSColor.whiteColor colorWithAlphaComponent:kActionBtnSubtitleAlpha]
		: NSColor.secondaryLabelColor;
	_detailLabel.textColor = NSColor.tertiaryLabelColor;
	_symbolView.contentTintColor = primary ? NSColor.whiteColor
		: (_presentationStyle == LuaActionButtonStyleRow
			? NSColor.secondaryLabelColor : NSColor.controlAccentColor);
}

- (void)layout {
	[super layout];
	CGFloat width = self.bounds.size.width;
	CGFloat height = self.bounds.size.height;
	_backgroundView.frame = self.bounds;
	BOOL link = _presentationStyle == LuaActionButtonStyleLink;
	BOOL hasSymbol = _symbolView.image != nil;
	BOOL hasSubtitle = _subtitleLabel.stringValue.length > 0;
	BOOL hasDetail = _detailLabel.stringValue.length > 0;
	CGFloat inset = link ? kActionBtnInsetLink
		: (_presentationStyle == LuaActionButtonStyleRow
			? kActionBtnInsetRow : kActionBtnInsetPlain);
	CGFloat iconWidth = hasSymbol
		? (_presentationStyle == LuaActionButtonStyleRow
			? kActionBtnIconWidthRow : kActionBtnIconWidth) : 0;
	CGFloat iconGap = hasSymbol ? kActionBtnIconGap : 0;
	CGFloat detailWidth = hasDetail ? kActionBtnDetailWidth : 0;
	CGFloat textX = inset + iconWidth + iconGap;
	CGFloat textWidth = MAX(0, width - textX - inset - detailWidth
		- (hasDetail ? kActionBtnDetailGap : 0));
	if (_presentationStyle == LuaActionButtonStylePrimary
		|| _presentationStyle == LuaActionButtonStylePlain) {
		textWidth = MAX(0, textWidth - kActionBtnTextExtraInset);
	}
	CGFloat titleHeight = ceil(_titleLabel.intrinsicContentSize.height);
	BOOL wrapsTitle = _presentationStyle != LuaActionButtonStyleRow
		&& _presentationStyle != LuaActionButtonStyleLink;
	if (wrapsTitle) {
		CGFloat naturalTitleWidth = [_titleLabel.stringValue sizeWithAttributes:
			@{NSFontAttributeName: _titleLabel.font}].width;
		if (naturalTitleWidth > textWidth) {
			titleHeight *= kActionBtnTitleMaxLines;
		}
	}
	CGFloat subtitleHeight = hasSubtitle
		? ceil(_subtitleLabel.intrinsicContentSize.height) : 0;
	CGFloat textGap = hasSubtitle ? kActionBtnTitleSubtitleGap : 0;
	CGFloat blockHeight = titleHeight + textGap + subtitleHeight;
	CGFloat blockBottom = floor((height - blockHeight) / 2);

	_symbolView.frame = NSMakeRect(
		inset, floor((height - iconWidth) / 2), iconWidth, iconWidth);
	_titleLabel.frame = NSMakeRect(
		textX, blockBottom, textWidth, titleHeight);
	_subtitleLabel.frame = NSMakeRect(
		textX, blockBottom + titleHeight + textGap, textWidth, subtitleHeight);
	_detailLabel.frame = NSMakeRect(
		MAX(textX, width - inset - detailWidth),
		floor((height - kActionBtnDetailHeight) / 2),
		detailWidth, kActionBtnDetailHeight);
}

@end
