#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

enum {
	kAxisKey,
	kFlexibleKey,
	kTableSourceKey,
	kCallbackKey,
	kToolbarDelegateKey,
	kColumnAlignmentKey,
	kColumnSystemImageKey,
	kResizeObserverKey,
	kPaddingKey,
	kPaddingHorizontalKey,
	kPaddingVerticalKey,
	kSpacingKey,
	kAlignmentKey,
	kFixedWidthKey,
	kFixedHeightKey,
	kMinWidthKey,
	kMinHeightKey,
	kMaxWidthKey,
	kMaxHeightKey,
	kFlexGrowKey,
	kFlexShrinkKey,
	kFlexBasisKey,
	kFillWidthKey,
	kFillHeightKey,
	kImageLayoutSizeKey,
	kTableSpinnerKey,
	kTableSelectionKey,
	kTableRefreshKey,
	kTextChangeKey,
	kTextWrapKey,
	kKeyCount
};
static char kKeys[kKeyCount];
static const CGFloat kStackSpacing = 8.0;
static lua_State *gL = NULL;

#include "lua_async.m"

typedef struct {
	void *ptr;
} ObjCRef;

static void push_objc(lua_State *L, id obj, const char *meta);

/* Protected Lua calls keep the host alive, but they must not make failures
 * invisible. Keep reporting at the native boundary so every AppKit callback
 * follows the same stderr contract, including unusual non-string errors. */
static void report_lua_error(lua_State *L, const char *context) {
	const char *message = lua_tostring(L, -1);
	if (message) {
		fprintf(stderr, "%s error: %s\n", context, message);
	} else {
		fprintf(stderr, "%s error: <%s>\n", context, luaL_typename(L, -1));
	}
	fflush(stderr);
}

#pragma mark - LuaTableViewSource

@interface LuaTableViewSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) NSTableView *tableView;
- (void)updateTableFrame;
@end

@interface LuaTableCellView : NSTableCellView
@end

@implementation LuaTableCellView

- (void)layout {
	[super layout];
	NSTextField *text = self.textField;
	if (!text) return;
	NSImageView *image = self.imageView;
	CGFloat imageWidth = image.image ? 16 : 0;
	CGFloat imageGap = imageWidth > 0 ? 6 : 0;
	CGFloat textX = 8 + imageWidth + imageGap;
	CGFloat height = ceil(text.intrinsicContentSize.height);
	text.frame = NSMakeRect(
		textX,
		floor((self.bounds.size.height - height) / 2),
		MAX(0, self.bounds.size.width - textX - 8),
		height);
	if (image) {
		image.frame = NSMakeRect(
			8,
			floor((self.bounds.size.height - imageWidth) / 2),
			imageWidth,
			imageWidth);
	}
}

@end

@implementation LuaTableViewSource

- (instancetype)initWithTableView:(NSTableView *)tv columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_tableView = tv;
		_columns = [cols mutableCopy];
		_rows = [NSMutableArray array];
		tv.dataSource = self;
		tv.delegate = self;
	}
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return (NSInteger)_rows.count;
}

- (void)updateTableFrame {
	NSClipView *clipView = (NSClipView *)_tableView.superview;
	if (![clipView isKindOfClass:[NSClipView class]]) return;

	CGFloat headerHeight = _tableView.headerView
		? _tableView.headerView.frame.size.height : 0;
	CGFloat rowsHeight = _rows.count * _tableView.rowHeight + headerHeight;
	NSSize viewport = clipView.bounds.size;
	CGRect frame = _tableView.frame;
	frame.size.width = viewport.width;
	frame.size.height = MAX(viewport.height, rowsHeight);
	_tableView.frame = frame;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)column
				  row:(NSInteger)row
{
	NSDictionary *rowData = _rows[row];
	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";

	NSString *reuseId = [@"cell-" stringByAppendingString:column.identifier];
	NSTableCellView *cell = [tableView makeViewWithIdentifier:reuseId owner:self];
	if (!cell) {
		cell = [[LuaTableCellView alloc] initWithFrame:
			NSMakeRect(0, 0, column.width, tableView.rowHeight)];
		cell.identifier = reuseId;

		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.bezeled = NO;
		tf.drawsBackground = NO;
		tf.editable = NO;
		tf.selectable = NO;
		tf.lineBreakMode = NSLineBreakByTruncatingTail;

		[cell addSubview:tf];
		cell.textField = tf;

		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		imageView.imageScaling = NSImageScaleProportionallyDown;
		imageView.contentTintColor = NSColor.secondaryLabelColor;
		[cell addSubview:imageView];
		cell.imageView = imageView;
	}
	cell.textField.stringValue = text;
	NSString *symbolName = objc_getAssociatedObject(
		column, &kKeys[kColumnSystemImageKey]);
	if (symbolName.length > 0) {
		NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
			accessibilityDescription:text];
		NSImageSymbolConfiguration *configuration =
			[NSImageSymbolConfiguration configurationWithPointSize:13
														 weight:NSFontWeightRegular];
		cell.imageView.image = [image imageWithSymbolConfiguration:configuration];
	} else {
		cell.imageView.image = nil;
	}
	NSNumber *alignment = objc_getAssociatedObject(column, &kKeys[kColumnAlignmentKey]);
	cell.textField.alignment = alignment
		? (NSTextAlignment)alignment.integerValue : NSTextAlignmentLeft;
	[cell setNeedsLayout:YES];
	return cell;
}

- (void)addRow:(NSDictionary *)row {
	[_rows addObject:row];
	NSInteger idx = (NSInteger)_rows.count - 1;
	[_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
					  withAnimation:NSTableViewAnimationSlideDown];
	[self updateTableFrame];
}

- (void)removeRowAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_rows.count) return;
	[_rows removeObjectAtIndex:(NSUInteger)index];
	[_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
					  withAnimation:NSTableViewAnimationSlideUp];
	[self updateTableFrame];
}

- (void)clearRows {
	[_rows removeAllObjects];
	[_tableView reloadData];
	[self updateTableFrame];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = _tableView.selectedRow;
	if (row < 0) return;

	NSScrollView *sv = _tableView.enclosingScrollView;
	if (!sv || !gL) return;

	NSNumber *refNum = objc_getAssociatedObject(sv, &kKeys[kTableSelectionKey]);
	if (!refNum) return;

	NSDictionary *rowData = _rows[row];
	lua_rawgeti(gL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(gL, sv, "nsview");
	lua_pushinteger(gL, (lua_Integer)row);
	lua_newtable(gL);
	for (NSString *key in rowData) {
		id value = rowData[key];
		const char *str = value && ![value isEqual:[NSNull null]]
			? [[value description] UTF8String] : NULL;
		lua_pushstring(gL, str ?: "");
		lua_setfield(gL, -2, [key UTF8String]);
	}
	int status = lua_pcall(gL, 3, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(gL, "table selection");
		lua_pop(gL, 1);
	}
}

@end

#pragma mark - LuaOutlineViewSource

/* NSOutlineView data source that mirrors a Lua-side tree of name/path/children
 * tables. Each row is an NSMutableDictionary with optional @"children" array.
 * Supports single-column display with systemImage (folder vs file icons). */
@interface LuaOutlineViewSource : NSObject <NSOutlineViewDataSource,
	NSOutlineViewDelegate> {
	NSMutableArray *_rootRows;      /* top-level items */
	NSOutlineView *_outlineView;
	NSArray     *_columns;
}
- (instancetype)initWithOutlineView:(NSOutlineView *)ov columns:(NSArray *)cols;
- (void)addRootItem:(NSDictionary *)item;
- (void)addChildItem:(NSDictionary *)item parent:(NSDictionary *)parent;
- (void)clearAll;
- (NSInteger)rowCount;
- (void)updateTableFrame;
@end

@implementation LuaOutlineViewSource

- (instancetype)initWithOutlineView:(NSOutlineView *)ov columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_outlineView = ov;
		_columns = [cols copy];
		_rootRows = [NSMutableArray array];
		ov.dataSource = self;
		ov.delegate = self;
	}
	return self;
}

- (void)dealloc {
	_outlineView.dataSource = nil;
	_outlineView.delegate = nil;
}

- (void)updateTableFrame {
	NSClipView *clipView = (NSClipView *)_outlineView.superview;
	if (![clipView isKindOfClass:[NSClipView class]]) return;

	CGFloat headerHeight = _outlineView.headerView
		? _outlineView.headerView.frame.size.height : 0;
	CGFloat rowsHeight = _outlineView.numberOfRows * _outlineView.rowHeight
		+ headerHeight;
	NSSize viewport = clipView.bounds.size;
	CGRect frame = _outlineView.frame;
	frame.size.width = viewport.width;
	frame.size.height = MAX(viewport.height, rowsHeight);
	_outlineView.frame = frame;
}

- (void)addRootItem:(NSDictionary *)item {
	[_rootRows addObject:[item mutableCopy]];
	[_outlineView reloadData];
	[self updateTableFrame];
}

- (void)addChildItem:(NSDictionary *)item parent:(NSMutableDictionary *)parent {
	NSMutableArray *children = parent[@"children"];
	if (!children) {
		children = [NSMutableArray array];
		parent[@"children"] = children;
	}
	[children addObject:[item mutableCopy]];
	[_outlineView reloadData];
	[self updateTableFrame];
}

- (void)clearAll {
	[_rootRows removeAllObjects];
	[_outlineView reloadData];
}

- (NSInteger)rowCount {
	return _outlineView.numberOfRows;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
	if (!item) return (NSInteger)_rootRows.count;
	return [(NSArray *)((NSDictionary *)item)[@"children"] count];
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(id)item {
	if (!item) return _rootRows[idx];
	return ((NSDictionary *)item)[@"children"][idx];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
	return ((NSDictionary *)item)[@"children"] != nil;
}

/* Single-column cells: use NSTextField in an NSTableCellView, matching the
 * NSTableView pattern. */
- (NSView *)outlineView:(NSOutlineView *)ov
	viewForTableColumn:(NSTableColumn *)column
				  item:(id)item
{
	NSDictionary *rowData = (NSDictionary *)item;
	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";

	NSString *reuseId = [@"outline-cell-" stringByAppendingString:colId];
	NSTableCellView *cell = [ov makeViewWithIdentifier:reuseId owner:self];
	if (!cell) {
		cell = [[LuaTableCellView alloc]
			initWithFrame:NSMakeRect(0, 0, column.width, ov.rowHeight)];
		cell.identifier = reuseId;

		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.bezeled = NO;
		tf.drawsBackground = NO;
		tf.editable = NO;
		tf.selectable = NO;
		tf.lineBreakMode = NSLineBreakByTruncatingTail;
		[cell addSubview:tf];
		cell.textField = tf;
	}
	cell.textField.stringValue = text;

	NSString *symbolName =
		objc_getAssociatedObject(column, &kKeys[kColumnSystemImageKey]);
	if (symbolName.length > 0) {
		NSString *iconName = rowData[@"children"] != nil
			? @"folder" : symbolName;
		NSImage *image = [NSImage imageWithSystemSymbolName:iconName
			accessibilityDescription:text];
		NSImageSymbolConfiguration *config =
			[NSImageSymbolConfiguration configurationWithPointSize:13
														 weight:NSFontWeightRegular];
		cell.imageView.image = [image imageWithSymbolConfiguration:config];
	} else {
		cell.imageView.image = nil;
	}

	NSNumber *alignment = objc_getAssociatedObject(column,
		&kKeys[kColumnAlignmentKey]);
	cell.textField.alignment = alignment
		? (NSTextAlignment)alignment.integerValue : NSTextAlignmentLeft;
	[cell setNeedsLayout:YES];
	return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = _outlineView.selectedRow;
	if (row < 0) return;

	NSScrollView *sv = _outlineView.enclosingScrollView;
	if (!sv || !gL) return;

	NSNumber *refNum = objc_getAssociatedObject(sv,
		&kKeys[kTableSelectionKey]);
	if (!refNum) return;

	id item = [_outlineView itemAtRow:row];
	if (!item) return;
	NSDictionary *rowData = (NSDictionary *)item;

	lua_rawgeti(gL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(gL, sv, "nsview");
	lua_pushinteger(gL, (lua_Integer)row);
	lua_newtable(gL);
	for (NSString *key in rowData) {
		if ([key isEqualToString:@"children"]) continue;
		id val = rowData[key];
		const char *str = val && ![val isEqual:[NSNull null]]
			? [[val description] UTF8String] : NULL;
		lua_pushstring(gL, str ?: "");
		lua_setfield(gL, -2, [key UTF8String]);
	}
	int status = lua_pcall(gL, 3, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(gL, "outline selection");
		lua_pop(gL, 1);
	}
}

@end

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
	int status = lua_pcall(gL, 1, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(gL, "button");
		lua_pop(gL, 1);
	}
}

@end

#pragma mark - Compound action button

static NSColor *semantic_color(NSString *name) {
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
@property (nonatomic, copy) NSString *presentationStyle;
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

	_presentationStyle = [style copy] ?: @"plain";
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
	_backgroundView.cornerRadius = 8;
	_backgroundView.contentViewMargins = NSZeroSize;

	_symbolView = [[NSImageView alloc] initWithFrame:NSZeroRect];
	if (symbol.length > 0) {
		NSImageSymbolConfiguration *configuration =
			[NSImageSymbolConfiguration configurationWithPointSize:
				[_presentationStyle isEqualToString:@"row"] ? 20 : 17
														 weight:NSFontWeightMedium];
		NSImage *image = [NSImage imageWithSystemSymbolName:symbol
			accessibilityDescription:title];
		_symbolView.image = [image imageWithSymbolConfiguration:configuration];
		_symbolView.imageScaling = NSImageScaleProportionallyDown;
	}

	_titleLabel = [NSTextField labelWithString:title ?: @""];
	_titleLabel.font = [NSFont systemFontOfSize:13 weight:
		[_presentationStyle isEqualToString:@"primary"]
			? NSFontWeightSemibold : NSFontWeightRegular];
	BOOL wrapsTitle = ![_presentationStyle isEqualToString:@"row"]
		&& ![_presentationStyle isEqualToString:@"link"];
	_titleLabel.lineBreakMode = wrapsTitle
		? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
	_titleLabel.maximumNumberOfLines = wrapsTitle ? 2 : 1;
	_titleLabel.cell.wraps = wrapsTitle;

	_subtitleLabel = [NSTextField labelWithString:subtitle ?: @""];
	_subtitleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
	_subtitleLabel.lineBreakMode = [_presentationStyle isEqualToString:@"row"]
		? NSLineBreakByTruncatingMiddle : NSLineBreakByTruncatingTail;
	_subtitleLabel.maximumNumberOfLines = 1;

	_detailLabel = [NSTextField labelWithString:detail ?: @""];
	_detailLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
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
	CGFloat height = 58;
	if ([_presentationStyle isEqualToString:@"primary"]) height = 64;
	if ([_presentationStyle isEqualToString:@"row"]) height = 52;
	if ([_presentationStyle isEqualToString:@"link"]) height = 40;
	return NSMakeSize(220, height);
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
	BOOL primary = [_presentationStyle isEqualToString:@"primary"];
	BOOL link = [_presentationStyle isEqualToString:@"link"];
	_backgroundView.cornerRadius = primary || !link ? 8 : 0;

	NSColor *background = NSColor.clearColor;
	if (primary) {
		background = _hovering
			? [NSColor.controlAccentColor colorWithAlphaComponent:0.85]
			: NSColor.controlAccentColor;
	} else if (_hovering) {
		background = [NSColor.labelColor colorWithAlphaComponent:0.07];
	}
	_backgroundView.fillColor = background;

	_titleLabel.textColor = primary ? NSColor.whiteColor
		: (link ? NSColor.controlAccentColor : NSColor.labelColor);
	_subtitleLabel.textColor = primary
		? [NSColor.whiteColor colorWithAlphaComponent:0.75]
		: NSColor.secondaryLabelColor;
	_detailLabel.textColor = NSColor.tertiaryLabelColor;
	_symbolView.contentTintColor = primary ? NSColor.whiteColor
		: ([_presentationStyle isEqualToString:@"row"]
			? NSColor.secondaryLabelColor : NSColor.controlAccentColor);
}

- (void)layout {
	[super layout];
	CGFloat width = self.bounds.size.width;
	CGFloat height = self.bounds.size.height;
	_backgroundView.frame = self.bounds;
	BOOL link = [_presentationStyle isEqualToString:@"link"];
	BOOL hasSymbol = _symbolView.image != nil;
	BOOL hasSubtitle = _subtitleLabel.stringValue.length > 0;
	BOOL hasDetail = _detailLabel.stringValue.length > 0;
	CGFloat inset = link ? 20 : ([_presentationStyle isEqualToString:@"row"] ? 14 : 12);
	CGFloat iconWidth = hasSymbol
		? ([_presentationStyle isEqualToString:@"row"] ? 28 : 24) : 0;
	CGFloat iconGap = hasSymbol ? 12 : 0;
	CGFloat detailWidth = hasDetail ? 72 : 0;
	CGFloat textX = inset + iconWidth + iconGap;
	CGFloat textWidth = MAX(0, width - textX - inset - detailWidth
		- (hasDetail ? 12 : 0));
	if ([_presentationStyle isEqualToString:@"primary"]
		|| [_presentationStyle isEqualToString:@"plain"]) {
		// SwiftUI's trailing Spacer keeps a small minimum even before it grows.
		// Reserving the same room makes long titles wrap at native welcome-panel
		// widths instead of crowding the button's trailing edge.
		textWidth = MAX(0, textWidth - 16);
	}
	CGFloat titleHeight = ceil(_titleLabel.intrinsicContentSize.height);
	BOOL wrapsTitle = ![_presentationStyle isEqualToString:@"row"]
		&& ![_presentationStyle isEqualToString:@"link"];
	if (wrapsTitle) {
		CGFloat naturalTitleWidth = [_titleLabel.stringValue sizeWithAttributes:
			@{NSFontAttributeName: _titleLabel.font}].width;
		if (naturalTitleWidth > textWidth) {
			titleHeight *= 2;
		}
	}
	CGFloat subtitleHeight = hasSubtitle
		? ceil(_subtitleLabel.intrinsicContentSize.height) : 0;
	CGFloat textGap = hasSubtitle ? 1 : 0;
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
		floor((height - 16) / 2), detailWidth, 16);
}

@end

#pragma mark - LuaToolbarDelegate

@interface LuaToolbarDelegate : NSObject <NSToolbarDelegate>
@property (nonatomic, strong) NSArray *items;
@end

@implementation LuaToolbarDelegate

- (instancetype)initWithItems:(NSArray *)items {
	self = [super init];
	if (self) {
		_items = [items copy];
	}
	return self;
}

- (NSArray<NSString *> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *item in _items) {
		[ids addObject:item[@"id"]];
	}
	return ids;
}

- (NSArray<NSString *> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	 itemForItemIdentifier:(NSString *)identifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	for (NSDictionary *item in _items) {
		if ([item[@"id"] isEqualToString:identifier]) {
			NSToolbarItem *ti = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
			ti.label = item[@"label"] ?: identifier;
			ti.paletteLabel = ti.label;
			ti.toolTip = item[@"tooltip"];
			ti.autovalidates = NO;
			ti.enabled = YES;

			NSImage *img = nil;
			if (item[@"icon"]) {
				img = [NSImage imageWithSystemSymbolName:item[@"icon"]
										accessibilityDescription:ti.label];
			}

			NSNumber *refNum = item[@"actionRef"];
			if (refNum) {
				objc_setAssociatedObject(ti, &kKeys[kCallbackKey], refNum,
					OBJC_ASSOCIATION_RETAIN);
				ti.target = [LuaButtonTarget shared];
				ti.action = @selector(onAction:);

				NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
				btn.bezelStyle = NSBezelStyleToolbar;
				btn.image = img;
				btn.imagePosition = img ? NSImageOnly : NSNoImage;
				btn.toolTip = ti.toolTip;
				[btn sizeToFit];
				btn.target = [LuaButtonTarget shared];
				btn.action = @selector(onAction:);
				objc_setAssociatedObject(btn, &kKeys[kCallbackKey], refNum,
					OBJC_ASSOCIATION_RETAIN);
				ti.view = btn;
			} else if (img) {
				ti.image = img;
			}

			return ti;
		}
	}
	return nil;
}

@end

#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_table_show_loading(lua_State *L);
static int bridge_table_hide_loading(lua_State *L);
static int bridge_table_set_refresh(lua_State *L);
static int bridge_table_refresh(lua_State *L);
static int bridge_table_set_selection(lua_State *L);
static int bridge_set_text(lua_State *L);
static int bridge_text_view(lua_State *L);
static int bridge_text_view_get_text(lua_State *L);
static int bridge_text_view_set_text(lua_State *L);
static int bridge_text_view_on_change(lua_State *L);
static int bridge_text_view_set_language(lua_State *L);
static int bridge_text_view_set_wrap_mode(lua_State *L);
static int bridge_symbol_toggle(lua_State *L);
static int bridge_eval(lua_State *L);
static int bridge_clear_container(lua_State *L);
static int bridge_outlineview(lua_State *L);
static int bridge_list_directory(lua_State *L);
static void layout_recursive(NSView *view, CGFloat width);

static void push_objc(lua_State *L, id obj, const char *meta) {
	ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
	ref->ptr = (void *)CFBridgingRetain(obj);
	luaL_setmetatable(L, meta);
}

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "nsview");
	if (ref) return (__bridge id)ref->ptr;
	ref = luaL_testudata(L, idx, "nswindow");
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "nsview or nswindow");
	return nil;
}

static NSView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	if ([obj isKindOfClass:[NSWindow class]]) {
		return [(NSWindow *)obj contentView];
	}
	return (NSView *)obj;
}

#define INDEX_NUMBER(name, kvar, fallback) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		lua_pushnumber(L, v ? v.doubleValue : fallback); \
		return 1; \
	}

#define INDEX_NUMBER_OR_NIL(name, kvar) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		if (v) lua_pushnumber(L, v.doubleValue); else lua_pushnil(L); \
		return 1; \
	}

#define INDEX_BOOL(name, kvar) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		lua_pushboolean(L, v.boolValue); \
		return 1; \
	}

#define INDEX_STRING(name, kvar, fallback) \
	if (strcmp(key, name) == 0) { \
		NSString *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		lua_pushstring(L, v ? v.UTF8String : fallback); \
		return 1; \
	}

#define NEWINDEX_NUMBER(name, kvar) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, &kKeys[kvar], @(luaL_checknumber(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

#define NEWINDEX_NUMBER_CLAMP(name, kvar, expr) \
	if (strcmp(key, name) == 0) { \
		double val = luaL_checknumber(L, 3); \
		objc_setAssociatedObject(obj, &kKeys[kvar], @(expr), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

#define NEWINDEX_NILABLE_NUMBER(name, kvar) \
	if (strcmp(key, name) == 0) { \
		if (lua_isnil(L, 3)) { \
			objc_setAssociatedObject(obj, &kKeys[kvar], nil, OBJC_ASSOCIATION_ASSIGN); \
		} else { \
			objc_setAssociatedObject(obj, &kKeys[kvar], @(luaL_checknumber(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		} \
		return 0; \
	}

#define NEWINDEX_NILABLE_NUMBER_CLAMP(name, kvar, expr) \
	if (strcmp(key, name) == 0) { \
		if (lua_isnil(L, 3)) { \
			objc_setAssociatedObject(obj, &kKeys[kvar], nil, OBJC_ASSOCIATION_ASSIGN); \
		} else { \
			double val = luaL_checknumber(L, 3); \
			objc_setAssociatedObject(obj, &kKeys[kvar], @(expr), OBJC_ASSOCIATION_RETAIN); \
		} \
		return 0; \
	}

#define NEWINDEX_BOOL(name, kvar) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, &kKeys[kvar], @(lua_toboolean(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

#define NEWINDEX_STRING(name, kvar) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, &kKeys[kvar], [NSString stringWithUTF8String:luaL_checkstring(L, 3)], OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

static int gc_objc(lua_State *L) {
	ObjCRef *ref = lua_touserdata(L, 1);
	if (ref->ptr) {
		CFRelease(ref->ptr);
		ref->ptr = NULL;
	}
	return 0;
}

static void push_objc_value(lua_State *L, id value) {
	if (!value || value == [NSNull null]) {
		lua_pushnil(L);
	} else if ([value isKindOfClass:[NSString class]]) {
		lua_pushstring(L, [(NSString *)value UTF8String]);
	} else if ([value isKindOfClass:[NSNumber class]]) {
		NSNumber *num = (NSNumber *)value;
		NSString *typeStr = [NSString stringWithUTF8String:num.objCType];
		if ([typeStr isEqualToString:@"c"] || [typeStr isEqualToString:@"B"]) {
			lua_pushboolean(L, num.boolValue);
		} else {
			lua_pushnumber(L, num.doubleValue);
		}
	} else if ([value isKindOfClass:[NSView class]]) {
		push_objc(L, value, "nsview");
	} else if ([value isKindOfClass:[NSWindow class]]) {
		push_objc(L, value, "nswindow");
	} else if ([value isKindOfClass:[NSObject class]]) {
		push_objc(L, value, "nsobject");
	} else {
		lua_pushstring(L, [[value description] UTF8String]);
	}
}

static id lua_to_objc_value(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "nsview");
	if (!ref) ref = luaL_testudata(L, idx, "nswindow");
	if (!ref) ref = luaL_testudata(L, idx, "nsobject");
	if (ref) return (__bridge id)ref->ptr;

	switch (lua_type(L, idx)) {
		case LUA_TNIL:
			return nil;
		case LUA_TBOOLEAN:
			return @(lua_toboolean(L, idx));
		case LUA_TNUMBER: {
			double d = lua_tonumber(L, idx);
			if (d == floor(d) && d <= (double)NSIntegerMax && d >= (double)NSIntegerMin)
				return @((NSInteger)d);
			return @(d);
		}
		case LUA_TSTRING:
			return [NSString stringWithUTF8String:lua_tostring(L, idx)];
		default:
			return nil;
	}
}

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	INDEX_NUMBER("padding", kPaddingKey, 0);
	INDEX_NUMBER("paddingHorizontal", kPaddingHorizontalKey, 0);
	INDEX_NUMBER("paddingVertical", kPaddingVerticalKey, 0);
	INDEX_NUMBER("spacing", kSpacingKey, kStackSpacing);
	INDEX_STRING("alignment", kAlignmentKey, "center");
	INDEX_NUMBER("fixedWidth", kFixedWidthKey, 0);
	INDEX_NUMBER("fixedHeight", kFixedHeightKey, 0);
	INDEX_NUMBER("minWidth", kMinWidthKey, 0);
	INDEX_NUMBER("minHeight", kMinHeightKey, 0);
	INDEX_NUMBER_OR_NIL("maxWidth", kMaxWidthKey);
	INDEX_NUMBER_OR_NIL("maxHeight", kMaxHeightKey);
	INDEX_NUMBER("flexGrow", kFlexGrowKey, 0);
	INDEX_NUMBER("flexShrink", kFlexShrinkKey, 1);
	INDEX_NUMBER_OR_NIL("flexBasis", kFlexBasisKey);
	INDEX_BOOL("fillWidth", kFillWidthKey);
	INDEX_BOOL("fillHeight", kFillHeightKey);

	if (strcmp(key, "set_text") == 0 && [obj isKindOfClass:[NSTextField class]]) {
		lua_pushcfunction(L, bridge_set_text);
		return 1;
	}

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	@try {
		id value = [obj valueForKey:kvcKey];
		push_objc_value(L, value);
		return 1;
	} @catch (NSException *e) {
	}

	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (src) {
		if (strcmp(key, "addRow") == 0) {
			lua_pushcfunction(L, bridge_tableview_add);
			return 1;
		}
		if (strcmp(key, "removeRow") == 0) {
			lua_pushcfunction(L, bridge_tableview_remove);
			return 1;
		}
		if (strcmp(key, "clearRows") == 0) {
			lua_pushcfunction(L, bridge_tableview_clear);
			return 1;
		}
		if (strcmp(key, "rowCount") == 0) {
			if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
				lua_pushinteger(L,
					(lua_Integer)[(LuaOutlineViewSource *)src rowCount]);
			} else {
				lua_pushinteger(L,
					(lua_Integer)((LuaTableViewSource *)src).rows.count);
			}
			return 1;
		}
		if (strcmp(key, "showLoading") == 0) {
			lua_pushcfunction(L, bridge_table_show_loading);
			return 1;
		}
		if (strcmp(key, "hideLoading") == 0) {
			lua_pushcfunction(L, bridge_table_hide_loading);
			return 1;
		}
		if (strcmp(key, "refresh") == 0) {
			lua_pushcfunction(L, bridge_table_refresh);
			return 1;
		}
		if (strcmp(key, "onRowSelect") == 0) {
			lua_pushcfunction(L, bridge_table_set_selection);
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

static int nsview_newindex(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) return luaL_error(L, "invalid property name");

	NEWINDEX_NUMBER("padding", kPaddingKey);
	NEWINDEX_NUMBER("paddingHorizontal", kPaddingHorizontalKey);
	NEWINDEX_NUMBER("paddingVertical", kPaddingVerticalKey);
	NEWINDEX_NUMBER_CLAMP("spacing", kSpacingKey, MAX(0, val));
	NEWINDEX_STRING("alignment", kAlignmentKey);
	NEWINDEX_NUMBER("fixedWidth", kFixedWidthKey);
	NEWINDEX_NUMBER("fixedHeight", kFixedHeightKey);
	NEWINDEX_NUMBER("minWidth", kMinWidthKey);
	NEWINDEX_NUMBER("minHeight", kMinHeightKey);
	NEWINDEX_NILABLE_NUMBER("maxWidth", kMaxWidthKey);
	NEWINDEX_NILABLE_NUMBER("maxHeight", kMaxHeightKey);
	NEWINDEX_NUMBER_CLAMP("flexGrow", kFlexGrowKey, MAX(0, val));
	NEWINDEX_NUMBER_CLAMP("flexShrink", kFlexShrinkKey, MAX(0, val));
	NEWINDEX_NILABLE_NUMBER_CLAMP("flexBasis", kFlexBasisKey, MAX(0, val));
	NEWINDEX_BOOL("fillWidth", kFillWidthKey);
	NEWINDEX_BOOL("fillHeight", kFillHeightKey);

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_objc_value(L, 3);

	@try {
		[obj setValue:value forKey:kvcKey];
	} @catch (NSException *e) {
		return luaL_error(L, "cannot set '%s': %s", key, e.description.UTF8String);
	}

	return 0;
}

#pragma mark - Bridge functions

static int bridge_window(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	int transparent_titlebar = lua_toboolean(L, 4);
	int hide_title = lua_toboolean(L, 5);

	NSRect frame = NSMakeRect(0, 0, width, height);
	NSUInteger style = NSWindowStyleMaskTitled
					 | NSWindowStyleMaskClosable
					 | NSWindowStyleMaskMiniaturizable
					 | NSWindowStyleMaskResizable;

	if (transparent_titlebar) {
		style |= NSWindowStyleMaskFullSizeContentView;
	}

	NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
											   styleMask:style
												 backing:NSBackingStoreBuffered
												   defer:NO];
	w.title = [NSString stringWithUTF8String:title];
	w.releasedWhenClosed = NO;

	if (transparent_titlebar) {
		w.titlebarAppearsTransparent = YES;
		if (hide_title) {
			w.titleVisibility = NSWindowTitleHidden;
		}
		w.movableByWindowBackground = YES;
	}

	[w center];

	[[NSNotificationCenter defaultCenter]
		addObserverForName:NSWindowWillCloseNotification
					object:w
					 queue:nil
				usingBlock:^(NSNotification *note) {
			/* App:present replaces windows while the run loop is alive. Defer
			 * termination until the close has completed so the replacement
			 * window is visible before deciding that the app has no UI left. */
			dispatch_async(dispatch_get_main_queue(), ^{
				BOOL hasVisibleWindow = NO;
				for (NSWindow *window in NSApp.windows) {
					if (window.isVisible) {
						hasVisibleWindow = YES;
						break;
					}
				}
				if (!hasVisibleWindow) {
					[NSApp terminate:nil];
				}
			});
		}];

	if (!lua_isnoneornil(L, 6)) {
		luaL_checktype(L, 6, LUA_TTABLE);
		int n = (int)luaL_len(L, 6);
		NSMutableArray *items = [NSMutableArray array];
		for (int i = 1; i <= n; i++) {
			lua_rawgeti(L, 6, i);
			lua_getfield(L, -1, "id");
			lua_getfield(L, -2, "label");
			lua_getfield(L, -3, "icon");
			const char *iid = lua_tostring(L, -3);
			const char *ilabel = lua_tostring(L, -2);
			const char *iicon = lua_tostring(L, -1);

			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			if (iid) dict[@"id"] = [NSString stringWithUTF8String:iid];
			if (ilabel) dict[@"label"] = [NSString stringWithUTF8String:ilabel];
			if (iicon) dict[@"icon"] = [NSString stringWithUTF8String:iicon];

			lua_pop(L, 1);

			lua_getfield(L, -3, "tooltip");
			const char *tooltip = lua_tostring(L, -1);
			if (tooltip) {
				dict[@"tooltip"] = [NSString stringWithUTF8String:tooltip];
			}
			lua_pop(L, 1);

			lua_getfield(L, -3, "action");
			if (lua_isfunction(L, -1)) {
				lua_pushvalue(L, -1);
				int ref = luaL_ref(L, LUA_REGISTRYINDEX);
				dict[@"actionRef"] = @(ref);
			}
			lua_pop(L, 1);

			[items addObject:dict];
			lua_pop(L, 3);
		}

		LuaToolbarDelegate *del = [[LuaToolbarDelegate alloc] initWithItems:items];
		NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"main"];
		tb.displayMode = lua_toboolean(L, 7)
			? NSToolbarDisplayModeIconAndLabel : NSToolbarDisplayModeIconOnly;
		tb.delegate = del;
		w.toolbar = tb;
		objc_setAssociatedObject(w, &kKeys[kToolbarDelegateKey], del,
			OBJC_ASSOCIATION_RETAIN);
	}

	push_objc(L, w, "nswindow");
	return 1;
}

static int bridge_vstack(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(v, &kKeys[kAxisKey], @"vstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_hstack(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(v, &kKeys[kAxisKey], @"hstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_hsplit(lua_State *L) {
	NSSplitView *v = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	v.vertical = YES;
	v.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(v, &kKeys[kAxisKey], @"hsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

/* VSplit — NSSplitView with vertical=NO, splits the area top-to-bottom.
 * Maps to Xcode's DVTSplitView used for editor/debug-area stacking. */
static int bridge_vsplit(lua_State *L) {
	NSSplitView *v = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	v.vertical = NO;
	v.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(v, &kKeys[kAxisKey], @"vsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

/* Thin horizontal separator line — like NSBox with NSBoxSeparator. */
static int bridge_separator(lua_State *L) {
	NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
	box.boxType = NSBoxSeparator;
	objc_setAssociatedObject(box, &kKeys[kFixedHeightKey], @1.0, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(box, &kKeys[kFillWidthKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, box, "nsview");
	return 1;
}

static int bridge_spacer(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
	objc_setAssociatedObject(v, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kKeys[kFlexBasisKey], @0, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

#pragma mark - Text update

#pragma mark - Image

@interface LuaImageViewerView : NSView <NSDraggingDestination>
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSImage *sourceImage;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic) CGFloat zoomScale;
@property (nonatomic) BOOL fitToWindow;
@property (nonatomic) int dropCallbackRef;
@end

@implementation LuaImageViewerView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_zoomScale = 1.0;
		_fitToWindow = NO;
		_dropCallbackRef = LUA_NOREF;

		_scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
		_scrollView.hasVerticalScroller = YES;
		_scrollView.hasHorizontalScroller = YES;
		_scrollView.autohidesScrollers = YES;
		_scrollView.borderType = NSNoBorder;
		_scrollView.drawsBackground = NO;

		_documentView = [[NSView alloc] initWithFrame:NSZeroRect];
		_imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		_imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
		_imageView.imageAlignment = NSImageAlignCenter;
		[_documentView addSubview:_imageView];
		_scrollView.documentView = _documentView;
		[self addSubview:_scrollView];
		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	}
	return self;
}

- (void)dealloc {
	if (_dropCallbackRef != LUA_NOREF && gL) {
		luaL_unref(gL, LUA_REGISTRYINDEX, _dropCallbackRef);
	}
}

- (BOOL)acceptsFirstResponder {
	return YES;
}

- (void)setFrame:(NSRect)frameRect {
	[super setFrame:frameRect];
	[self updateLayout];
}

- (void)layout {
	[super layout];
	[self updateLayout];
}

- (void)setImagePath:(NSString *)imagePath {
	_imagePath = [imagePath copy];
	NSString *path = _imagePath;
	NSImage *image = nil;
	if (path.length > 0) {
		image = [[NSImage alloc] initWithContentsOfFile:path];
		if (!image) {
			image = [NSImage imageNamed:path];
		}
	}
	_sourceImage = image;
	_imageView.image = image;
	[self updateLayout];
}

- (void)setZoomScale:(CGFloat)zoomScale {
	_zoomScale = MAX(0.05, zoomScale);
	if (!_fitToWindow) {
		[self updateLayout];
	}
}

- (void)setFitToWindow:(BOOL)fitToWindow {
	_fitToWindow = fitToWindow;
	[self updateLayout];
}

- (NSArray<NSString *> *)dropPathsFromPasteboard:(NSPasteboard *)pasteboard {
	NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
		options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	for (NSURL *url in urls) {
		if (url.isFileURL && url.path.length > 0) {
			[paths addObject:url.path];
		}
	}
	return paths;
}

- (BOOL)hasFileDrop:(id<NSDraggingInfo>)sender {
	return [self dropPathsFromPasteboard:sender.draggingPasteboard].count > 0;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	return [self hasFileDrop:sender] ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	return [self hasFileDrop:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSArray<NSString *> *paths = [self dropPathsFromPasteboard:sender.draggingPasteboard];
	if (paths.count == 0) return NO;
	if (_dropCallbackRef == LUA_NOREF || !gL) return YES;

	lua_State *callL = gL;
	lua_rawgeti(callL, LUA_REGISTRYINDEX, _dropCallbackRef);
	lua_newtable(callL);
	for (NSUInteger i = 0; i < paths.count; i++) {
		lua_pushstring(callL, paths[i].UTF8String);
		lua_rawseti(callL, -2, (lua_Integer)(i + 1));
	}
	if (lua_pcall(callL, 1, 0, 0) != LUA_OK) {
		report_lua_error(callL, "image drop");
		lua_pop(callL, 1);
	}
	return YES;
}

- (void)updateLayout {
	self.scrollView.frame = self.bounds;
	NSImage *image = self.sourceImage;
	if (!image) {
		self.documentView.frame = self.scrollView.bounds;
		self.imageView.frame = NSZeroRect;
		return;
	}

	NSSize source = image.size;
	if (source.width <= 0 || source.height <= 0) {
		source = NSMakeSize(1, 1);
	}

	NSSize viewport = self.scrollView.contentSize;
	CGFloat scale = self.fitToWindow
		? MIN(viewport.width / source.width, viewport.height / source.height)
		: self.zoomScale;
	if (!isfinite(scale) || scale <= 0) {
		scale = 1.0;
	}
	CGFloat imageWidth = MAX(1, round(source.width * scale));
	CGFloat imageHeight = MAX(1, round(source.height * scale));
	CGFloat docWidth = MAX(viewport.width, imageWidth);
	CGFloat docHeight = MAX(viewport.height, imageHeight);

	self.documentView.frame = NSMakeRect(0, 0, docWidth, docHeight);
	self.imageView.frame = NSMakeRect(
		floor((docWidth - imageWidth) / 2.0),
		floor((docHeight - imageHeight) / 2.0),
		imageWidth,
		imageHeight);
	self.scrollView.hasHorizontalScroller = docWidth > viewport.width;
	self.scrollView.hasVerticalScroller = docHeight > viewport.height;
}

@end

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];
	CGFloat maxWidth = luaL_optnumber(L, 2, 400.0);

	NSImage *img = [[NSImage alloc] initWithContentsOfFile:nsPath];
	if (!img) {
		img = [NSImage imageNamed:nsPath];
	}
	if (!img) {
		return luaL_error(L, "failed to load image: %s", path);
	}

	NSSize size = img.size;
	if (maxWidth > 0 && size.width > maxWidth) {
		CGFloat ratio = maxWidth / size.width;
		size.width = maxWidth;
		size.height *= ratio;
	}

	NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
	iv.image = img;
	iv.imageScaling = NSImageScaleProportionallyUpOrDown;
	// NSImageView reports the source bitmap's intrinsic dimensions even when
	// the bridge has capped its display frame. Preserve the intended display
	// size so stack measurement does not reserve space for the original image.
	objc_setAssociatedObject(iv, &kKeys[kImageLayoutSizeKey],
		[NSValue valueWithSize:size], OBJC_ASSOCIATION_RETAIN);

	push_objc(L, iv, "nsview");
	return 1;
}

static int bridge_image_viewer(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	int ref = LUA_NOREF;
	if (!lua_isnoneornil(L, 2)) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	LuaImageViewerView *viewer = [[LuaImageViewerView alloc]
		initWithFrame:NSMakeRect(0, 0, 640, 480)];
	viewer.dropCallbackRef = ref;
	viewer.imagePath = [NSString stringWithUTF8String:path];

	push_objc(L, viewer, "nsview");
	return 1;
}

static int bridge_system_image(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *description = luaL_optstring(L, 2, symbol);
	CGFloat pointSize = luaL_optnumber(L, 3, 17);
	const char *weightName = luaL_optstring(L, 4, "regular");
	const char *colorName = luaL_optstring(L, 5, "accent");

	NSFontWeight weight = NSFontWeightRegular;
	if (strcmp(weightName, "semibold") == 0) weight = NSFontWeightSemibold;
	else if (strcmp(weightName, "medium") == 0) weight = NSFontWeightMedium;
	else if (strcmp(weightName, "light") == 0) weight = NSFontWeightLight;
	else if (strcmp(weightName, "bold") == 0) weight = NSFontWeightBold;

	NSString *name = [NSString stringWithUTF8String:symbol];
	NSString *accessibilityDescription =
		[NSString stringWithUTF8String:description];
	NSImage *image = [NSImage imageWithSystemSymbolName:name
		accessibilityDescription:accessibilityDescription];
	if (!image) return luaL_error(L, "unknown SF Symbol: %s", symbol);

	NSImageSymbolConfiguration *configuration =
		[NSImageSymbolConfiguration configurationWithPointSize:pointSize
													   weight:weight];
	image = [image imageWithSymbolConfiguration:configuration];
	NSImageView *view = [[NSImageView alloc]
		initWithFrame:NSMakeRect(0, 0, pointSize, pointSize)];
	view.image = image;
	view.imageScaling = NSImageScaleProportionallyDown;
	view.contentTintColor = semantic_color(
		[NSString stringWithUTF8String:colorName]);
	view.accessibilityLabel = accessibilityDescription;
	push_objc(L, view, "nsview");
	return 1;
}

static int bridge_system_color(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	NSColor *color = semantic_color([NSString stringWithUTF8String:name]);
	push_objc(L, color, "nsobject");
	return 1;
}

static int bridge_add(lua_State *L) {
	id parent = check_objc(L, 1);
	NSView *child = check_view(L, 2);

	NSView *container;
	if ([parent isKindOfClass:[NSWindow class]]) {
		NSWindow *window = (NSWindow *)parent;
		container = window.contentView;
		child.frame = container.bounds;
		child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

		if (!objc_getAssociatedObject(window, &kKeys[kResizeObserverKey])) {
			__weak NSView *weakChild = child;
			id observer = [[NSNotificationCenter defaultCenter]
				addObserverForName:NSWindowDidResizeNotification
							object:window
							 queue:nil
						usingBlock:^(NSNotification *note) {
							NSView *root = weakChild;
							if (!root) return;
							root.frame = ((NSWindow *)note.object).contentView.bounds;
							layout_recursive(root, root.bounds.size.width);
						}];
			objc_setAssociatedObject(window, &kKeys[kResizeObserverKey], observer,
				OBJC_ASSOCIATION_RETAIN);
		}
	} else {
		container = (NSView *)parent;
	}

	[container addSubview:child];
	return 0;
}

static BOOL is_flexible(NSView *view) {
	return [objc_getAssociatedObject(view, &kKeys[kFlexibleKey]) boolValue];
}

static CGFloat view_padding_horizontal(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingHorizontalKey]);
	if (value) return value.doubleValue;
	NSNumber *p = objc_getAssociatedObject(view, &kKeys[kPaddingKey]);
	return p ? p.doubleValue : 0;
}

static CGFloat view_padding_vertical(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingVerticalKey]);
	if (value) return value.doubleValue;
	NSNumber *p = objc_getAssociatedObject(view, &kKeys[kPaddingKey]);
	return p ? p.doubleValue : 0;
}

static CGFloat view_spacing(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kSpacingKey]);
	return value ? value.doubleValue : kStackSpacing;
}

static NSString *view_alignment(NSView *view) {
	return objc_getAssociatedObject(view, &kKeys[kAlignmentKey]) ?: @"center";
}

static CGFloat view_fixed_width(NSView *view) {
	NSNumber *w = objc_getAssociatedObject(view, &kKeys[kFixedWidthKey]);
	return w ? w.doubleValue : 0;
}

static CGFloat view_fixed_height(NSView *view) {
	NSNumber *h = objc_getAssociatedObject(view, &kKeys[kFixedHeightKey]);
	return h ? h.doubleValue : 0;
}

static CGFloat view_optional_dimension(NSView *view, const void *key, CGFloat fallback) {
	NSNumber *value = objc_getAssociatedObject(view, key);
	return value ? value.doubleValue : fallback;
}

static CGFloat clamp_dimension(CGFloat value, CGFloat minimum, CGFloat maximum) {
	value = MAX(value, minimum);
	if (isfinite(maximum)) value = MIN(value, maximum);
	return MAX(0, value);
}

static BOOL default_grows_on_axis(NSView *view, BOOL horizontal) {
	if (!is_flexible(view)) return NO;
	NSString *axis = objc_getAssociatedObject(view, &kKeys[kAxisKey]);
	if (!horizontal && [axis isEqualToString:@"hstack"]) return NO;
	if (horizontal && [axis isEqualToString:@"vsplit"]) return NO;
	return YES;
}

static CGFloat view_flex_grow(NSView *view, BOOL horizontal) {
	if ((horizontal && view_fixed_width(view) > 0) ||
		(!horizontal && view_fixed_height(view) > 0)) {
		return 0;
	}
	NSNumber *grow = objc_getAssociatedObject(view, &kKeys[kFlexGrowKey]);
	if (grow) return MAX(0, grow.doubleValue);
	return default_grows_on_axis(view, horizontal) ? 1 : 0;
}

static CGFloat view_flex_shrink(NSView *view, BOOL horizontal) {
	if ((horizontal && view_fixed_width(view) > 0) ||
		(!horizontal && view_fixed_height(view) > 0)) {
		return 0;
	}
	NSNumber *shrink = objc_getAssociatedObject(view, &kKeys[kFlexShrinkKey]);
	if (shrink) return MAX(0, shrink.doubleValue);
	return is_flexible(view) ? 1 : 0;
}

static BOOL view_fills_cross_axis(NSView *view, BOOL horizontal) {
	const void *key = horizontal ? &kKeys[kFillWidthKey] : &kKeys[kFillHeightKey];
	NSNumber *fill = objc_getAssociatedObject(view, key);
	return fill ? fill.boolValue : view_flex_grow(view, horizontal) > 0;
}

typedef NS_ENUM(NSInteger, LuaMeasureMode) {
	LuaMeasureUndefined,
	LuaMeasureAtMost,
	LuaMeasureExactly,
};

typedef struct {
	CGFloat width;
	CGFloat height;
	LuaMeasureMode widthMode;
	LuaMeasureMode heightMode;
} LuaLayoutConstraint;

static NSSize measure_view(NSView *view, LuaLayoutConstraint constraint);

static CGFloat constrained_result(CGFloat natural, CGFloat proposal,
								  LuaMeasureMode mode) {
	if (mode == LuaMeasureExactly) return MAX(0, proposal);
	if (mode == LuaMeasureAtMost) return MIN(MAX(0, natural), MAX(0, proposal));
	return MAX(0, natural);
}

static NSSize measure_leaf(NSView *view) {
	NSSize size = view.frame.size;
	NSSize intrinsic = view.intrinsicContentSize;
	if (intrinsic.width != NSViewNoIntrinsicMetric && intrinsic.width >= 0) {
		size.width = MAX(size.width, intrinsic.width);
	}
	if (intrinsic.height != NSViewNoIntrinsicMetric && intrinsic.height >= 0) {
		size.height = MAX(size.height, intrinsic.height);
	}

	NSSize fitting = view.fittingSize;
	if (fitting.width > 0) size.width = MAX(size.width, fitting.width);
	if (fitting.height > 0) size.height = MAX(size.height, fitting.height);
	if (size.width <= 0) size.width = 1;
	if (size.height <= 0) size.height = 22;
	return size;
}

static NSSize measure_view(NSView *view, LuaLayoutConstraint constraint) {
	if (!view) return NSZeroSize;

	NSString *axis = objc_getAssociatedObject(view, &kKeys[kAxisKey]);
	CGFloat padX = view_padding_horizontal(view);
	CGFloat padY = view_padding_vertical(view);
	CGFloat innerWidth = constraint.widthMode == LuaMeasureUndefined
		? 0 : MAX(0, constraint.width - 2 * padX);
	CGFloat innerHeight = constraint.heightMode == LuaMeasureUndefined
		? 0 : MAX(0, constraint.height - 2 * padY);
	NSSize natural = NSZeroSize;

	if ([axis isEqualToString:@"vstack"]) {
		NSUInteger count = view.subviews.count;
		for (NSView *child in view.subviews) {
			LuaLayoutConstraint childConstraint = {
				.width = innerWidth,
				.height = 0,
				.widthMode = constraint.widthMode == LuaMeasureUndefined
					? LuaMeasureUndefined : LuaMeasureAtMost,
				.heightMode = LuaMeasureUndefined,
			};
			NSSize childSize = measure_view(child, childConstraint);
			natural.width = MAX(natural.width, childSize.width);
			natural.height += childSize.height;
		}
		if (count > 1) natural.height += (count - 1) * view_spacing(view);
		natural.width += 2 * padX;
		natural.height += 2 * padY;
	} else if ([axis isEqualToString:@"hstack"]) {
		NSUInteger count = view.subviews.count;
		for (NSView *child in view.subviews) {
			LuaLayoutConstraint childConstraint = {
				.width = 0,
				.height = innerHeight,
				.widthMode = LuaMeasureUndefined,
				.heightMode = constraint.heightMode == LuaMeasureUndefined
					? LuaMeasureUndefined : LuaMeasureAtMost,
			};
			NSSize childSize = measure_view(child, childConstraint);
			natural.width += childSize.width;
			natural.height = MAX(natural.height, childSize.height);
		}
		if (count > 1) natural.width += (count - 1) * view_spacing(view);
		natural.width += 2 * padX;
		natural.height += 2 * padY;
	} else if ([axis isEqualToString:@"hsplit"]) {
		for (NSView *child in view.subviews) {
			CGFloat fw = view_fixed_width(child);
			NSSize childSize;
			if (fw > 0) {
				childSize = NSMakeSize(fw, 0);
			} else {
				childSize = measure_view(child, (LuaLayoutConstraint){
					.width = 0,
					.height = innerHeight,
					.widthMode = LuaMeasureUndefined,
					.heightMode = constraint.heightMode == LuaMeasureUndefined
						? LuaMeasureUndefined : LuaMeasureAtMost,
				});
			}
			natural.width += childSize.width;
			natural.height = MAX(natural.height, childSize.height);
		}
		CGFloat dividers = view.subviews.count > 1
			? (view.subviews.count - 1) * [(NSSplitView *)view dividerThickness] : 0;
		natural.width += dividers + 2 * padX;
		natural.height += 2 * padY;
	} else if ([axis isEqualToString:@"vsplit"]) {
		for (NSView *child in view.subviews) {
			CGFloat fh = view_fixed_height(child);
			NSSize childSize;
			if (fh > 0) {
				childSize = NSMakeSize(0, fh);
			} else {
				childSize = measure_view(child, (LuaLayoutConstraint){
					.width = innerWidth,
					.height = 0,
					.widthMode = constraint.widthMode == LuaMeasureUndefined
						? LuaMeasureUndefined : LuaMeasureAtMost,
					.heightMode = LuaMeasureUndefined,
				});
			}
			natural.width = MAX(natural.width, childSize.width);
			natural.height += childSize.height;
		}
		CGFloat dividers = view.subviews.count > 1
			? (view.subviews.count - 1) * [(NSSplitView *)view dividerThickness] : 0;
		natural.width += 2 * padX;
		natural.height += dividers + 2 * padY;
	} else {
		NSValue *imageLayoutSize =
			objc_getAssociatedObject(view, &kKeys[kImageLayoutSizeKey]);
		if (imageLayoutSize) {
			natural = imageLayoutSize.sizeValue;
			CGFloat scale = 1;
			if (constraint.widthMode != LuaMeasureUndefined
				&& natural.width > constraint.width && natural.width > 0) {
				scale = MIN(scale, constraint.width / natural.width);
			}
			if (constraint.heightMode != LuaMeasureUndefined
				&& natural.height > constraint.height && natural.height > 0) {
				scale = MIN(scale, constraint.height / natural.height);
			}
			natural.width *= MAX(0, scale);
			natural.height *= MAX(0, scale);
		} else {
			natural = measure_leaf(view);
		}
	}

	CGFloat fixedWidth = view_fixed_width(view);
	CGFloat fixedHeight = view_fixed_height(view);
	if (fixedWidth > 0) natural.width = fixedWidth;
	if (fixedHeight > 0) natural.height = fixedHeight;

	natural.width = clamp_dimension(
		natural.width,
		view_optional_dimension(view, &kKeys[kMinWidthKey], 0),
		view_optional_dimension(view, &kKeys[kMaxWidthKey], INFINITY));
	natural.height = clamp_dimension(
		natural.height,
		view_optional_dimension(view, &kKeys[kMinHeightKey], 0),
		view_optional_dimension(view, &kKeys[kMaxHeightKey], INFINITY));

	if (fixedWidth <= 0) {
		natural.width = constrained_result(
			natural.width, constraint.width, constraint.widthMode);
	}
	if (fixedHeight <= 0) {
		natural.height = constrained_result(
			natural.height, constraint.height, constraint.heightMode);
	}
	return natural;
}

static void distribute_main_axis(NSArray<NSView *> *children, CGFloat *sizes,
								 CGFloat available, BOOL horizontal) {
	NSUInteger count = children.count;
	if (count == 0) return;

	CGFloat used = 0;
	for (NSUInteger i = 0; i < count; i++) used += sizes[i];
	CGFloat freeSpace = available - used;
	if (fabs(freeSpace) < 0.5) return;

	BOOL growing = freeSpace > 0;
	BOOL *frozen = calloc(count, sizeof(BOOL));
	for (NSUInteger pass = 0; pass < count && fabs(freeSpace) >= 0.5; pass++) {
		CGFloat totalWeight = 0;
		for (NSUInteger i = 0; i < count; i++) {
			if (frozen[i]) continue;
			NSView *child = children[i];
			CGFloat weight = growing
				? view_flex_grow(child, horizontal)
				: view_flex_shrink(child, horizontal) * MAX(1, sizes[i]);
			totalWeight += weight;
		}
		if (totalWeight <= 0) break;

		CGFloat distributed = 0;
		BOOL hitBound = NO;
		for (NSUInteger i = 0; i < count; i++) {
			if (frozen[i]) continue;
			NSView *child = children[i];
			CGFloat weight = growing
				? view_flex_grow(child, horizontal)
				: view_flex_shrink(child, horizontal) * MAX(1, sizes[i]);
			if (weight <= 0) continue;

			CGFloat delta = freeSpace * weight / totalWeight;
			CGFloat minimum = view_optional_dimension(child,
				horizontal ? &kKeys[kMinWidthKey] : &kKeys[kMinHeightKey], 0);
			CGFloat maximum = view_optional_dimension(child,
				horizontal ? &kKeys[kMaxWidthKey] : &kKeys[kMaxHeightKey], INFINITY);
			CGFloat proposed = sizes[i] + delta;
			CGFloat clamped = clamp_dimension(proposed, minimum, maximum);
			distributed += clamped - sizes[i];
			sizes[i] = clamped;
			if (fabs(clamped - proposed) >= 0.5) {
				frozen[i] = YES;
				hitBound = YES;
			}
		}
		freeSpace -= distributed;
		if (!hitBound) break;
	}
	free(frozen);
}

static void layout_recursive(NSView *view, CGFloat width) {
	if (!view) return;

	NSString *axis = objc_getAssociatedObject(view, &kKeys[kAxisKey]);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;

	if ([axis isEqualToString:@"vstack"] || [axis isEqualToString:@"hstack"] ||
		[axis isEqualToString:@"hsplit"] || [axis isEqualToString:@"vsplit"]) {

		CGFloat padX = view_padding_horizontal(view);
		CGFloat padY = view_padding_vertical(view);
		CGFloat stackSpacing = view_spacing(view);
		CGFloat contentW = availableWidth - 2 * padX;
		CGFloat contentH = availableHeight - 2 * padY;
		NSString *alignment = view_alignment(view);

		if ([axis isEqualToString:@"vstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat *heights = calloc(count, sizeof(CGFloat));
			NSMutableArray<NSValue *> *measured = [NSMutableArray arrayWithCapacity:count];
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				NSSize size = measure_view(child, (LuaLayoutConstraint){
					.width = contentW,
					.height = 0,
					.widthMode = LuaMeasureAtMost,
					.heightMode = LuaMeasureUndefined,
				});
				NSNumber *basis = objc_getAssociatedObject(child, &kKeys[kFlexBasisKey]);
				CGFloat fixed = view_fixed_height(child);
				heights[i] = clamp_dimension(
					fixed > 0 ? fixed : (basis ? basis.doubleValue : size.height),
					view_optional_dimension(child, &kKeys[kMinHeightKey], 0),
					view_optional_dimension(child, &kKeys[kMaxHeightKey], INFINITY));
				[measured addObject:[NSValue valueWithSize:size]];
			}
			distribute_main_axis(view.subviews, heights,
				MAX(0, contentH - spacing), NO);
			CGFloat top = padY + contentH;

			for (NSUInteger i = 0; i < count; i++) {
				NSView *sv = view.subviews[i];
				CGFloat childH = heights[i];
				NSSize natural = measured[i].sizeValue;
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = fw > 0 ? fw
					: (view_fills_cross_axis(sv, YES) ? contentW
						: MIN(natural.width, contentW));
				childW = clamp_dimension(
					childW,
					view_optional_dimension(sv, &kKeys[kMinWidthKey], 0),
					view_optional_dimension(sv, &kKeys[kMaxWidthKey], INFINITY));
				top -= childH;
				CGFloat childX = padX;
				if ([alignment isEqualToString:@"center"]) {
					childX = padX + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = padX + contentW - childW;
				}
				sv.frame = NSMakeRect(childX, top, childW, childH);
				layout_recursive(sv, childW);
				top -= stackSpacing;
			}
			free(heights);
		} else if ([axis isEqualToString:@"hstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat *widths = calloc(count, sizeof(CGFloat));
			NSMutableArray<NSValue *> *measured = [NSMutableArray arrayWithCapacity:count];
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				NSSize size = measure_view(child, (LuaLayoutConstraint){
					.width = 0,
					.height = contentH,
					.widthMode = LuaMeasureUndefined,
					.heightMode = LuaMeasureAtMost,
				});
				NSNumber *basis = objc_getAssociatedObject(child, &kKeys[kFlexBasisKey]);
				CGFloat fixed = view_fixed_width(child);
				widths[i] = clamp_dimension(
					fixed > 0 ? fixed : (basis ? basis.doubleValue : size.width),
					view_optional_dimension(child, &kKeys[kMinWidthKey], 0),
					view_optional_dimension(child, &kKeys[kMaxWidthKey], INFINITY));
				[measured addObject:[NSValue valueWithSize:size]];
			}
			distribute_main_axis(view.subviews, widths,
				MAX(0, contentW - spacing), YES);
			CGFloat x = padX;

			for (NSUInteger i = 0; i < count; i++) {
				NSView *sv = view.subviews[i];
				CGFloat childW = widths[i];
				NSSize natural = measured[i].sizeValue;
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = fh > 0 ? fh
					: (view_fills_cross_axis(sv, NO) ? contentH
						: MIN(natural.height, contentH));
				childH = clamp_dimension(
					childH,
					view_optional_dimension(sv, &kKeys[kMinHeightKey], 0),
					view_optional_dimension(sv, &kKeys[kMaxHeightKey], INFINITY));
				CGFloat childY = padY;
				if ([alignment isEqualToString:@"center"]) {
					childY = padY + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"top"]) {
					childY = padY + contentH - childH;
				}
				sv.frame = NSMakeRect(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + stackSpacing;
			}
			free(widths);
		} else if ([axis isEqualToString:@"hsplit"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat divider = [(NSSplitView *)view dividerThickness];
			CGFloat spacing = count > 1 ? (count - 1) * divider : 0;
			CGFloat *widths = calloc(count, sizeof(CGFloat));
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				NSSize size = measure_view(child, (LuaLayoutConstraint){
					.width = 0,
					.height = contentH,
					.widthMode = LuaMeasureUndefined,
					.heightMode = LuaMeasureAtMost,
				});
				NSNumber *basis = objc_getAssociatedObject(child, &kKeys[kFlexBasisKey]);
				CGFloat fixed = view_fixed_width(child);
				widths[i] = clamp_dimension(
					fixed > 0 ? fixed : (basis ? basis.doubleValue : size.width),
					view_optional_dimension(child, &kKeys[kMinWidthKey], 0),
					view_optional_dimension(child, &kKeys[kMaxWidthKey], INFINITY));
			}
			distribute_main_axis(view.subviews, widths,
				MAX(0, contentW - spacing), YES);
			CGFloat x = padX;

			for (NSUInteger i = 0; i < count; i++) {
				NSView *sv = view.subviews[i];
				CGFloat childW = widths[i];
				sv.frame = NSMakeRect(x, padY, childW, contentH);
				layout_recursive(sv, childW);
				x += childW + divider;
			}
			free(widths);
		} else if ([axis isEqualToString:@"vsplit"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat divider = [(NSSplitView *)view dividerThickness];
			CGFloat spacing = count > 1 ? (count - 1) * divider : 0;
			CGFloat *heights = calloc(count, sizeof(CGFloat));
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				NSSize size = measure_view(child, (LuaLayoutConstraint){
					.width = contentW,
					.height = 0,
					.widthMode = LuaMeasureAtMost,
					.heightMode = LuaMeasureUndefined,
				});
				NSNumber *basis = objc_getAssociatedObject(child, &kKeys[kFlexBasisKey]);
				CGFloat fixed = view_fixed_height(child);
				heights[i] = clamp_dimension(
					fixed > 0 ? fixed : (basis ? basis.doubleValue : size.height),
					view_optional_dimension(child, &kKeys[kMinHeightKey], 0),
					view_optional_dimension(child, &kKeys[kMaxHeightKey], INFINITY));
			}
			distribute_main_axis(view.subviews, heights,
				MAX(0, contentH - spacing), NO);
			CGFloat top = padY + contentH;

			for (NSUInteger i = 0; i < count; i++) {
				NSView *sv = view.subviews[i];
				CGFloat childH = heights[i];
				top -= childH;
				sv.frame = NSMakeRect(padX, top, contentW, childH);
				layout_recursive(sv, contentW);
				top -= divider;
			}
			free(heights);
		}
	} else {
		if ([view isKindOfClass:[NSScrollView class]]) {
			LuaTableViewSource *source =
				objc_getAssociatedObject(view, &kKeys[kTableSourceKey]);
			[source updateTableFrame];
		}
		for (NSView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kKeys[kAxisKey])) {
				layout_recursive(sv, width);
			}
		}
	}
}

static int bridge_layout(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_optnumber(L, 2, 400);

	NSView *view;
	if ([obj isKindOfClass:[NSWindow class]]) {
		view = [(NSWindow *)obj contentView];
	} else {
		view = (NSView *)obj;
	}

	layout_recursive(view, width);
	return 0;
}

static int bridge_view_size(lua_State *L) {
	NSView *view = check_view(L, 1);
	lua_pushnumber(L, view.frame.size.width);
	lua_pushnumber(L, view.frame.size.height);
	return 2;
}

static int bridge_set_content_size(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	if ([obj isKindOfClass:[NSWindow class]]) {
		NSWindow *w = (NSWindow *)obj;
		NSRect frame = w.frame;
		NSRect contentRect = [w contentRectForFrameRect:frame];
		contentRect.size = NSMakeSize(width, height);
		NSRect newFrame = [w frameRectForContentRect:contentRect];
		[w setFrame:newFrame display:YES animate:NO];
	} else {
		NSView *v = (NSView *)obj;
		v.frame = NSMakeRect(v.frame.origin.x, v.frame.origin.y, width, height);
	}
	return 0;
}

static int bridge_set_window_min_size(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "setWindowMinSize requires a window");
	}
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	((NSWindow *)obj).contentMinSize = NSMakeSize(width, height);
	return 0;
}

static int bridge_set_appearance(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *name = luaL_checkstring(L, 2);

	if (strcmp(name, "system") == 0) {
		if ([obj isKindOfClass:[NSWindow class]]) {
			((NSWindow *)obj).appearance = nil;
		} else if ([obj isKindOfClass:[NSView class]]) {
			((NSView *)obj).appearance = nil;
		}
		return 0;
	}

	NSString *appearanceName = strcmp(name, "dark") == 0
		? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
	NSAppearance *appearance = [NSAppearance appearanceNamed:appearanceName];
	if ([obj isKindOfClass:[NSWindow class]]) {
		((NSWindow *)obj).appearance = appearance;
	} else if ([obj isKindOfClass:[NSView class]]) {
		((NSView *)obj).appearance = appearance;
	}
	return 0;
}

#pragma mark - Text update

static int bridge_set_text(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *str = luaL_checkstring(L, 2);
	if ([obj isKindOfClass:[NSTextField class]]) {
		NSTextField *textField = (NSTextField *)obj;
		[textField setStringValue:[NSString stringWithUTF8String:str]];
		[textField sizeToFit];

		NSView *layoutRoot = nil;
		for (NSView *ancestor = textField.superview;
			 ancestor != nil; ancestor = ancestor.superview) {
			if (objc_getAssociatedObject(ancestor, &kKeys[kAxisKey])) {
				layoutRoot = ancestor;
			}
		}
		if (layoutRoot) {
			layout_recursive(layoutRoot, layoutRoot.bounds.size.width);
		}
	}
	return 0;
}

#pragma mark - Button, toggle, separator

static int bridge_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	int has_action = !lua_isnoneornil(L, 2);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
	btn.title = [NSString stringWithUTF8String:title];
	btn.bezelStyle = NSBezelStyleRounded;
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		btn.target = [LuaButtonTarget shared];
		btn.action = @selector(onAction:);
	}

	push_objc(L, btn, "nsview");
	return 1;
}

static int bridge_action_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	const char *subtitle = luaL_optstring(L, 2, "");
	const char *symbol = luaL_optstring(L, 3, "");
	const char *style = luaL_optstring(L, 4, "plain");
	const char *detail = luaL_optstring(L, 5, "");
	BOOL hasAction = !lua_isnoneornil(L, 6);
	int ref = LUA_NOREF;
	if (hasAction) {
		luaL_checktype(L, 6, LUA_TFUNCTION);
		lua_pushvalue(L, 6);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	LuaActionButton *button = [[LuaActionButton alloc]
		initWithTitle:[NSString stringWithUTF8String:title]
			subtitle:[NSString stringWithUTF8String:subtitle]
			  symbol:[NSString stringWithUTF8String:symbol]
			  detail:[NSString stringWithUTF8String:detail]
			   style:[NSString stringWithUTF8String:style]];
	if (hasAction) {
		objc_setAssociatedObject(button, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		button.target = [LuaButtonTarget shared];
		button.action = @selector(onAction:);
	}
	push_objc(L, button, "nsview");
	return 1;
}

static int bridge_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	int is_on = lua_toboolean(L, 2);
	int has_action = !lua_isnoneornil(L, 3);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSButton *btn = [NSButton checkboxWithTitle:[NSString stringWithUTF8String:label]
										 target:nil action:nil];
	btn.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		btn.target = [LuaButtonTarget shared];
		btn.action = @selector(onAction:);
	}

	push_objc(L, btn, "nsview");
	return 1;
}

#pragma mark - Timer & spinner

static id lua_to_objc_recursive(lua_State *L, int idx);

static NSMutableDictionary *lua_table_to_dict(lua_State *L, int idx) {
	return (NSMutableDictionary *)lua_to_objc_recursive(L, idx);
}

/* Convert a Lua table (string or integer keys) to an ObjC collection.
 * String-keyed subtables become NSMutableDictionary, array-indexed ones
 * become NSMutableArray.  Leaf values become NSString.  This preserves
 * the tree structure needed by LuaOutlineViewSource. */
static id lua_to_objc_recursive(lua_State *L, int idx) {
	lua_pushvalue(L, idx);
	lua_pushnil(L);
	int firstKeyType = lua_next(L, -2) != 0 ? lua_type(L, -2) : LUA_TNIL;
	if (firstKeyType != LUA_TNIL) lua_pop(L, 2);  /* pop key+value */
	lua_pop(L, 1);  /* pop pushed copy */

	if (firstKeyType == LUA_TNIL) {
		/* Empty table — return empty dict */
		return [NSMutableDictionary dictionary];
	}

	if (firstKeyType == LUA_TNUMBER || firstKeyType == LUA_TSTRING) {
		BOOL isArray = (firstKeyType == LUA_TNUMBER);
		id result = isArray ? (id)[NSMutableArray array]
			: (id)[NSMutableDictionary dictionary];

		lua_pushvalue(L, idx);
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			id value = nil;
			if (lua_type(L, -1) == LUA_TTABLE) {
				value = lua_to_objc_recursive(L, lua_gettop(L));
			} else {
				const char *str = lua_tostring(L, -1);
				value = str ? [NSString stringWithUTF8String:str] : @"";
			}

			if (isArray) {
				[(NSMutableArray *)result addObject:value];
			} else {
				const char *key = lua_tostring(L, -2);
				if (key) {
					[(NSMutableDictionary *)result
						setObject:value
						forKey:[NSString stringWithUTF8String:key]];
				}
			}
			lua_pop(L, 1);
		}
		lua_pop(L, 1);

		return result;
	}

	/* Not a table — shouldn't happen */
	return [NSMutableDictionary dictionary];
}

static int bridge_tableview(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	BOOL showsHeader = YES;
	BOOL bordered = NO;
	NSString *tableStyle = nil;
	if (lua_istable(L, 4)) {
		lua_getfield(L, 4, "header");
		if (!lua_isnil(L, -1)) showsHeader = lua_toboolean(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 4, "bordered");
		if (!lua_isnil(L, -1)) bordered = lua_toboolean(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 4, "style");
		const char *style = lua_tostring(L, -1);
		if (style) tableStyle = [NSString stringWithUTF8String:style];
		lua_pop(L, 1);
	}

	int ncols = (int)luaL_len(L, 1);

	NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	if ([tableStyle isEqualToString:@"plain"]) {
		// Automatic styling adds end padding when a headerless table sits in a
		// sidebar. Plain is the native edge-to-edge style for compact file lists.
		tv.style = NSTableViewStylePlain;
	} else if ([tableStyle isEqualToString:@"fullWidth"]) {
		tv.style = NSTableViewStyleFullWidth;
	} else if ([tableStyle isEqualToString:@"inset"]) {
		tv.style = NSTableViewStyleInset;
	} else if ([tableStyle isEqualToString:@"sourceList"]) {
		tv.style = NSTableViewStyleSourceList;
	}
	tv.headerView = showsHeader ? [[NSTableHeaderView alloc] init] : nil;
	tv.usesAlternatingRowBackgroundColors = YES;
	tv.intercellSpacing = NSMakeSize(3, 2);
	tv.allowsColumnReordering = NO;
	tv.allowsColumnResizing = YES;
	CGFloat colW = ncols > 0 ? width / ncols : width;
	NSMutableArray *colSpecs = [NSMutableArray array];

	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		lua_getfield(L, -1, "id");
		lua_getfield(L, -2, "title");
		lua_getfield(L, -3, "alignment");
		lua_getfield(L, -4, "width");
		lua_getfield(L, -5, "systemImage");
		const char *colId = lua_tostring(L, -5);
		const char *colTitle = lua_tostring(L, -4);
		const char *colAlignment = lua_tostring(L, -3);
		CGFloat requestedWidth = lua_isnumber(L, -2)
			? lua_tonumber(L, -2) : colW;
		const char *systemImage = lua_tostring(L, -1);

		if (!colId) {
			lua_pop(L, 6);
			continue;
		}

		NSString *nsId = [NSString stringWithUTF8String:colId];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:nsId];
		col.title = [NSString stringWithUTF8String:colTitle ?: colId];
		col.width = requestedWidth;
		col.minWidth = 40;
		NSTextAlignment alignment = NSTextAlignmentLeft;
		if (colAlignment && strcmp(colAlignment, "trailing") == 0) {
			alignment = NSTextAlignmentRight;
		} else if (colAlignment && strcmp(colAlignment, "center") == 0) {
			alignment = NSTextAlignmentCenter;
		}
		col.headerCell.alignment = alignment;
		objc_setAssociatedObject(col, &kKeys[kColumnAlignmentKey], @(alignment),
			OBJC_ASSOCIATION_RETAIN);
		if (systemImage) {
			objc_setAssociatedObject(col, &kKeys[kColumnSystemImageKey],
				[NSString stringWithUTF8String:systemImage],
				OBJC_ASSOCIATION_RETAIN);
		}
		[tv addTableColumn:col];

		[colSpecs addObject:@{@"id": nsId, @"title": col.title}];

		lua_pop(L, 6);
	}
	tv.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];

	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	sv.documentView = tv;
	sv.hasVerticalScroller = YES;
	sv.autohidesScrollers = YES;
	sv.borderType = bordered ? NSBezelBorder : NSNoBorder;
	objc_setAssociatedObject(sv, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);

	objc_setAssociatedObject(sv, &kKeys[kTableSourceKey], src, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, sv, "nsview");
	return 1;
}

static int bridge_toolbar_item(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *identifier = luaL_checkstring(L, 2);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "ToolbarItem requires a window");
	}

	NSString *wanted = [NSString stringWithUTF8String:identifier];
	for (NSToolbarItem *item in ((NSWindow *)obj).toolbar.items) {
		if ([item.itemIdentifier isEqualToString:wanted]) {
			push_objc(L, item, "nsobject");
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

static int bridge_tableview_add(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");

	luaL_checktype(L, 2, LUA_TTABLE);
	NSMutableDictionary *row = lua_table_to_dict(L, 2);
	if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
		[(LuaOutlineViewSource *)src addRootItem:row];
	} else {
		[(LuaTableViewSource *)src addRow:row];
	}
	return 0;
}

static int bridge_tableview_remove(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	int idx = (int)luaL_checkinteger(L, 2);
	[src removeRowAtIndex:(NSInteger)idx];
	return 0;
}

static int bridge_tableview_clear(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");

	if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
		[(LuaOutlineViewSource *)src clearAll];
	} else {
		[(LuaTableViewSource *)src clearRows];
	}
	return 0;
}

static int bridge_table_show_loading(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSScrollView *sv = (NSScrollView *)obj;
	NSProgressIndicator *spinner = objc_getAssociatedObject(sv, &kKeys[kTableSpinnerKey]);
	if (spinner) {
		[spinner startAnimation:nil];
		return 0;
	}

	spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
	spinner.style = NSProgressIndicatorStyleSpinning;
	spinner.controlSize = NSControlSizeRegular;
	spinner.displayedWhenStopped = NO;
	[spinner sizeToFit];

	CGFloat sw = spinner.frame.size.width;
	CGFloat sh = spinner.frame.size.height;
	spinner.frame = NSMakeRect(
		(sv.bounds.size.width - sw) / 2,
		(sv.bounds.size.height - sh) / 2,
		sw, sh);
	spinner.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin
		| NSViewMinYMargin | NSViewMaxYMargin;

	objc_setAssociatedObject(sv, &kKeys[kTableSpinnerKey], spinner,
		OBJC_ASSOCIATION_RETAIN);
	[sv addSubview:spinner];
	[spinner startAnimation:nil];
	return 0;
}

static int bridge_table_hide_loading(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSScrollView *sv = (NSScrollView *)obj;
	NSProgressIndicator *spinner = objc_getAssociatedObject(sv, &kKeys[kTableSpinnerKey]);
	if (spinner) {
		[spinner stopAnimation:nil];
		[spinner removeFromSuperview];
		objc_setAssociatedObject(sv, &kKeys[kTableSpinnerKey], nil,
			OBJC_ASSOCIATION_RETAIN);
	}
	return 0;
}

static int bridge_table_set_refresh(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	objc_setAssociatedObject(obj, &kKeys[kTableRefreshKey], @(ref),
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_table_refresh(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSNumber *refNum = objc_getAssociatedObject(obj, &kKeys[kTableRefreshKey]);
	if (!refNum) { lua_pushboolean(L, 0); return 1; }

	lua_rawgeti(L, LUA_REGISTRYINDEX, refNum.intValue);
	lua_pushvalue(L, 1);
	if (!lua_isnoneornil(L, 2)) {
		lua_pushvalue(L, 2);
	} else {
		lua_pushnil(L);
	}
	int status = lua_pcall(L, 2, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(L, "refresh");
		lua_pop(L, 1);
	}
	lua_pushboolean(L, 1);
	return 1;
}

static int bridge_table_set_selection(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	if (lua_isnoneornil(L, 2)) {
		objc_setAssociatedObject(obj, &kKeys[kTableSelectionKey], nil,
			OBJC_ASSOCIATION_ASSIGN);
		return 0;
	}

	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	objc_setAssociatedObject(obj, &kKeys[kTableSelectionKey], @(ref),
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

#pragma mark - Outline View

static int bridge_outlineview(lua_State *L) {
	BOOL bordered = NO;
	BOOL header = YES;
	NSString *tableStyle = nil;

	luaL_checktype(L, 1, LUA_TTABLE);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	if (lua_gettop(L) >= 4 && lua_istable(L, 4)) {
		lua_getfield(L, 4, "header");
		header = lua_isnil(L, -1) ? YES : lua_toboolean(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 4, "bordered");
		bordered = lua_toboolean(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 4, "style");
		const char *style = lua_tostring(L, -1);
		if (style) tableStyle = [NSString stringWithUTF8String:style];
		lua_pop(L, 1);
	}

	NSOutlineView *ov = [[NSOutlineView alloc]
		initWithFrame:NSMakeRect(0, 0, width, height)];
	if ([tableStyle isEqualToString:@"plain"]) {
		ov.style = NSTableViewStylePlain;
	} else if ([tableStyle isEqualToString:@"fullWidth"]) {
		ov.style = NSTableViewStyleFullWidth;
	} else if ([tableStyle isEqualToString:@"inset"]) {
		ov.style = NSTableViewStyleInset;
	} else if ([tableStyle isEqualToString:@"sourceList"]) {
		ov.style = NSTableViewStyleSourceList;
	}
	ov.headerView = header ? [[NSTableHeaderView alloc] init] : nil;
	ov.usesAlternatingRowBackgroundColors = YES;
	ov.rowHeight = 24;
	ov.intercellSpacing = NSMakeSize(3, 2);
	ov.allowsColumnReordering = NO;
	ov.allowsColumnResizing = YES;
	ov.indentationPerLevel = 16;
	ov.indentationMarkerFollowsCell = YES;
	ov.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

	int ncols = (int)luaL_len(L, 1);
	CGFloat colW = ncols > 0 ? width / ncols : width;
	NSMutableArray *colSpecs = [NSMutableArray array];

	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		lua_getfield(L, -1, "id");
		lua_getfield(L, -2, "title");
		lua_getfield(L, -3, "alignment");
		lua_getfield(L, -4, "width");
		lua_getfield(L, -5, "systemImage");
		const char *colId = lua_tostring(L, -5);
		const char *colTitle = lua_tostring(L, -4);
		const char *colAlignment = lua_tostring(L, -3);
		CGFloat requestedWidth = lua_isnumber(L, -2)
			? lua_tonumber(L, -2) : colW;
		const char *systemImage = lua_tostring(L, -1);

		if (!colId) { lua_pop(L, 6); continue; }

		NSString *nsId = [NSString stringWithUTF8String:colId];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:nsId];
		col.title = [NSString stringWithUTF8String:colTitle ?: colId];
		col.width = requestedWidth;
		col.minWidth = 40;
		NSTextAlignment alignment = NSTextAlignmentLeft;
		if (colAlignment && strcmp(colAlignment, "trailing") == 0)
			alignment = NSTextAlignmentRight;
		else if (colAlignment && strcmp(colAlignment, "center") == 0)
			alignment = NSTextAlignmentCenter;
		col.headerCell.alignment = alignment;
		objc_setAssociatedObject(col, &kKeys[kColumnAlignmentKey],
			@(alignment), OBJC_ASSOCIATION_RETAIN);
		if (systemImage) {
			objc_setAssociatedObject(col, &kKeys[kColumnSystemImageKey],
				[NSString stringWithUTF8String:systemImage],
				OBJC_ASSOCIATION_RETAIN);
		}
		[ov addTableColumn:col];
		[colSpecs addObject:@{@"id": nsId, @"title": col.title}];
		lua_pop(L, 6);
	}

	LuaOutlineViewSource *src = [[LuaOutlineViewSource alloc]
		initWithOutlineView:ov columns:colSpecs];

	NSScrollView *sv = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(0, 0, width, height)];
	sv.documentView = ov;
	sv.hasVerticalScroller = YES;
	sv.autohidesScrollers = YES;
	sv.borderType = bordered ? NSBezelBorder : NSNoBorder;
	objc_setAssociatedObject(sv, &kKeys[kFlexibleKey], @YES,
		OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(sv, &kKeys[kTableSourceKey], src,
		OBJC_ASSOCIATION_RETAIN);

	push_objc(L, sv, "nsview");
	return 1;
}

#pragma mark - Directory listing

/* Internal helper: list directory contents into a Lua table on the stack.
 * path and depth are C strings/ints, not read from the Lua stack.
 * Always pushes exactly one value (the result table, or nil on error). */
static void list_dir_into_table(lua_State *L, const char *raw, int depth) {
	NSString *dirPath = [NSString stringWithUTF8String:raw];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *contents = [fm contentsOfDirectoryAtPath:dirPath error:nil];
	if (!contents) { lua_pushnil(L); return; }

	/* Sort: directories first, then alpha by name */
	contents = [contents sortedArrayUsingComparator:^NSComparisonResult(
		id a, id b) {
		NSString *pa = [dirPath stringByAppendingPathComponent:a];
		NSString *pb = [dirPath stringByAppendingPathComponent:b];
		BOOL ad = NO, bd = NO;
		[fm fileExistsAtPath:pa isDirectory:&ad];
		[fm fileExistsAtPath:pb isDirectory:&bd];
		if (ad != bd) return ad ? NSOrderedAscending : NSOrderedDescending;
		return [(NSString *)a caseInsensitiveCompare:(NSString *)b];
	}];

	lua_newtable(L);
	int ti = 1;

	for (NSString *name in contents) {
		NSString *full = [dirPath stringByAppendingPathComponent:name];
		BOOL isDir = NO;
		[fm fileExistsAtPath:full isDirectory:&isDir];

		/* Skip hidden files/directories */
		if ([name hasPrefix:@"."]) continue;

		lua_newtable(L);
		lua_pushstring(L, name.UTF8String);
		lua_setfield(L, -2, "name");
		lua_pushstring(L, full.UTF8String);
		lua_setfield(L, -2, "path");
		if (isDir) {
			lua_pushboolean(L, 1);
			lua_setfield(L, -2, "directory");
			if (depth > 0) {
				list_dir_into_table(L, full.UTF8String, depth - 1);
				lua_setfield(L, -2, "children");
			}
		}
		lua_rawseti(L, -2, ti++);
	}
}

static int bridge_list_directory(lua_State *L) {
	const char *raw = luaL_checkstring(L, 1);
	int depth = lua_isnumber(L, 2) ? (int)lua_tointeger(L, 2) : 0;
	list_dir_into_table(L, raw, depth);
	return 1;
}

#pragma mark - Show

static int bridge_show(lua_State *L) {
	NSWindow *w = (__bridge NSWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;

	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[w makeKeyAndOrderFront:nil];

	dispatch_async(dispatch_get_main_queue(), ^{
		[NSApp activateIgnoringOtherApps:YES];
		[w makeKeyAndOrderFront:nil];
	});

	return 0;
}

#pragma mark - Generic bridge (_create, _font, _perform, _callback)

static int bridge_create(lua_State *L) {
	const char *className = luaL_checkstring(L, 1);
	Class cls = NSClassFromString([NSString stringWithUTF8String:className]);
	if (!cls) return luaL_error(L, "unknown class: %s", className);

	id obj = [[cls alloc] init];
	push_objc(L, obj, [obj isKindOfClass:[NSWindow class]] ? "nswindow" : "nsview");
	return 1;
}

static int bridge_font(lua_State *L) {
	CGFloat size = luaL_checknumber(L, 1);
	const char *weightStr = luaL_optstring(L, 2, NULL);

	NSFontWeight w = NSFontWeightRegular;
	if (weightStr) {
		if (strcmp(weightStr, "bold") == 0) w = NSFontWeightBold;
		else if (strcmp(weightStr, "semibold") == 0) w = NSFontWeightSemibold;
		else if (strcmp(weightStr, "light") == 0) w = NSFontWeightLight;
		else if (strcmp(weightStr, "heavy") == 0) w = NSFontWeightHeavy;
	}

	NSFont *font = [NSFont systemFontOfSize:size weight:w];
	push_objc(L, font, "nsobject");
	return 1;
}

static int bridge_perform(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *selName = luaL_checkstring(L, 2);
	SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
	if (![obj respondsToSelector:sel]) return 0;

	id arg = nil;
	if (!lua_isnoneornil(L, 3)) {
		arg = lua_to_objc_value(L, 3);
	}

	NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
	if (!sig) return 0;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	inv.target = obj;
	inv.selector = sel;
	if (sig.numberOfArguments > 2) {
		[inv setArgument:&arg atIndex:2];
	}
	[inv invoke];

	if (sig.methodReturnLength > 0) {
		const char *retType = sig.methodReturnType;
		if (strcmp(retType, @encode(BOOL)) == 0 || strcmp(retType, "B") == 0 || strcmp(retType, "c") == 0) {
			BOOL val = NO;
			[inv getReturnValue:&val];
			lua_pushboolean(L, val);
		} else if (strcmp(retType, @encode(NSInteger)) == 0 || strcmp(retType, "q") == 0) {
			NSInteger val = 0;
			[inv getReturnValue:&val];
			lua_pushinteger(L, (lua_Integer)val);
		} else if (strcmp(retType, @encode(CGFloat)) == 0 || strcmp(retType, "d") == 0) {
			CGFloat val = 0;
			[inv getReturnValue:&val];
			lua_pushnumber(L, val);
		} else if (strcmp(retType, "@") == 0) {
			__unsafe_unretained id val = nil;
			[inv getReturnValue:&val];
			push_objc_value(L, val);
		} else {
			lua_pushnil(L);
		}
		return 1;
	}
	return 0;
}

static int bridge_callback(lua_State *L) {
	id obj = check_objc(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	objc_setAssociatedObject(obj, &kKeys[kCallbackKey], @(ref), OBJC_ASSOCIATION_RETAIN);
	if ([obj respondsToSelector:@selector(setTarget:)]) {
		[obj setTarget:[LuaButtonTarget shared]];
	}
	if ([obj respondsToSelector:@selector(setAction:)]) {
		[obj setAction:@selector(onAction:)];
	}

	return 0;
}

#include "syntax_highlight.m"

#pragma mark - NSTextView (code editor)

static int bridge_text_view(lua_State *L) {
	NSScrollView *sv = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(0, 0, 400, 300)];
	sv.hasVerticalScroller = YES;
	sv.hasHorizontalScroller = NO;
	sv.autohidesScrollers = YES;
	sv.borderType = NSNoBorder;

	NSSize contentSize = sv.contentSize;

	/* Use SyntaxTextStorage so syntax highlighting works */
	SyntaxTextStorage *storage = [[SyntaxTextStorage alloc] init];
	NSLayoutManager   *lm      = [[NSLayoutManager alloc] init];
	NSTextContainer   *tc      = [[NSTextContainer alloc]
		initWithContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
	tc.widthTracksTextView = NO;
	[lm addTextContainer:tc];
	[storage addLayoutManager:lm];

	NSTextView *tv = [[NSTextView alloc]
		initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)
		textContainer:tc];
	tv.font = [NSFont monospacedSystemFontOfSize:13
		weight:NSFontWeightRegular];
	tv.editable = YES;
	tv.selectable = YES;
	tv.automaticQuoteSubstitutionEnabled = NO;
	tv.automaticDashSubstitutionEnabled = NO;
	tv.automaticTextReplacementEnabled = NO;
	tv.richText = YES;  /* must be YES to render attributed colors */
	tv.allowsUndo = YES;
	tv.minSize = NSMakeSize(0, 0);
	tv.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
	tv.verticallyResizable = YES;
	tv.horizontallyResizable = YES;

	sv.hasHorizontalScroller = YES;
	sv.documentView = tv;
	objc_setAssociatedObject(sv, &kKeys[kTextWrapKey], @NO, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(sv, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, sv, "nsview");
	return 1;
}

static int bridge_text_view_get_text(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSScrollView class]]) {
		return luaL_error(L, "expected a text view");
	}
	NSTextView *tv = (NSTextView *)((NSScrollView *)obj).documentView;
	lua_pushstring(L, tv.string.UTF8String);
	return 1;
}

static int bridge_text_view_set_text(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *str = luaL_checkstring(L, 2);
	if (![obj isKindOfClass:[NSScrollView class]]) {
		return luaL_error(L, "expected a text view");
	}
	NSTextView *tv = (NSTextView *)((NSScrollView *)obj).documentView;
	tv.string = [NSString stringWithUTF8String:str];
	return 0;
}

static int bridge_text_view_on_change(lua_State *L) {
	id obj = check_objc(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);

	if (![obj isKindOfClass:[NSScrollView class]]) {
		return luaL_error(L, "expected a text view");
	}
	NSTextView *tv = (NSTextView *)((NSScrollView *)obj).documentView;

	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	objc_setAssociatedObject(tv, &kKeys[kTextChangeKey], @(ref),
		OBJC_ASSOCIATION_RETAIN);

	/* Same coroutine caveat: extraspace inherits from the main thread. */
	LuaStateOwner *owner = owner_for_state(L);

	[[NSNotificationCenter defaultCenter]
		addObserverForName:NSTextDidChangeNotification
					object:tv
					 queue:nil
				usingBlock:^(NSNotification *note) {
		NSNumber *refNum = objc_getAssociatedObject(note.object,
			&kKeys[kTextChangeKey]);
		if (!refNum || !owner) return;
		lua_State *callL = owner.L;
		if (!callL) return;
		lua_rawgeti(callL, LUA_REGISTRYINDEX, refNum.intValue);
		lua_pushstring(callL,
			((NSTextView *)note.object).string.UTF8String);
		if (lua_pcall(callL, 1, 0, 0) != LUA_OK) {
			report_lua_error(callL, "text change");
			lua_pop(callL, 1);
		}
	}];

	return 0;
}

static int bridge_text_view_set_language(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *lang = luaL_checkstring(L, 2);

	if (![obj isKindOfClass:[NSScrollView class]]) {
		return luaL_error(L, "expected a text view");
	}
	NSTextView *tv = (NSTextView *)((NSScrollView *)obj).documentView;
	SyntaxTextStorage *storage = (SyntaxTextStorage *)tv.textStorage;
	if ([storage isKindOfClass:[SyntaxTextStorage class]]) {
		storage.language = [NSString stringWithUTF8String:lang];
	}
	return 0;
}

/* Toggle word wrap on/off. Wrap ON tracks the visible width; wrap OFF
 * lets the text view grow horizontally with a scroll bar. */
static int bridge_text_view_set_wrap_mode(lua_State *L) {
	id obj = check_objc(L, 1);
	int wrap = lua_toboolean(L, 2);

	if (![obj isKindOfClass:[NSScrollView class]]) {
		return luaL_error(L, "expected a text view");
	}
	NSScrollView *sv = (NSScrollView *)obj;
	NSTextView *tv = (NSTextView *)sv.documentView;
	NSTextContainer *tc = tv.textContainer;

	if (wrap) {
		tv.horizontallyResizable = NO;
		tc.widthTracksTextView = YES;
		tc.containerSize = NSMakeSize(sv.contentSize.width, FLT_MAX);
		sv.hasHorizontalScroller = NO;
	} else {
		tv.horizontallyResizable = YES;
		tc.widthTracksTextView = NO;
		tc.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
		sv.hasHorizontalScroller = YES;
	}

	objc_setAssociatedObject(sv, &kKeys[kTextWrapKey],
		@(wrap), OBJC_ASSOCIATION_RETAIN);
	return 0;
}

/* Symbol toggle: an NSButton with an SF Symbol, acting as an on/off toggle.
 * Args: symbolName, tooltip, initialState, callback(optional) */
static int bridge_symbol_toggle(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *tooltip = luaL_optstring(L, 2, "");
	int state = lua_toboolean(L, 3);
	int has_action = !lua_isnoneornil(L, 4);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 4, LUA_TFUNCTION);
		lua_pushvalue(L, 4);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSString *name = [NSString stringWithUTF8String:symbol];
	NSImage *img = [NSImage imageWithSystemSymbolName:name
		accessibilityDescription:[NSString stringWithUTF8String:tooltip]];
	if (!img) {
		if (has_action) luaL_unref(L, LUA_REGISTRYINDEX, ref);
		return luaL_error(L, "unknown SF Symbol: %s", symbol);
	}

	NSImageSymbolConfiguration *config =
		[NSImageSymbolConfiguration configurationWithPointSize:13
														weight:NSFontWeightMedium];
	img = [img imageWithSymbolConfiguration:config];

	NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
	btn.title = @"";
	btn.image = img;
	btn.imagePosition = NSImageOnly;
	btn.bezelStyle = NSBezelStyleRounded;
	btn.buttonType = NSButtonTypeOnOff;
	btn.state = state ? NSControlStateValueOn : NSControlStateValueOff;
	btn.toolTip = [NSString stringWithUTF8String:tooltip];
	btn.accessibilityLabel = btn.toolTip;
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		btn.target = [LuaButtonTarget shared];
		btn.action = @selector(onAction:);
	}

	push_objc(L, btn, "nsview");
	return 1;
}

#include "canvas_eval.m"

#pragma mark - Offscreen render

static NSData *offscreen_render(NSView *view, CGFloat width, CGFloat height) {
	view.frame = NSMakeRect(0, 0, width, height);

	/* Wrap in a borderless offscreen window so drawRect: has a valid window. */
	NSWindow *offscreen = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(-10000, -10000, width, height)
				  styleMask:NSWindowStyleMaskBorderless
					backing:NSBackingStoreBuffered
					  defer:NO];
	offscreen.releasedWhenClosed = NO;
	[offscreen.contentView addSubview:view];
	[offscreen orderBack:nil];

	NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
	if (!rep) {
		[view removeFromSuperview];
		[offscreen close];
		return nil;
	}

	CGFloat scale = [NSScreen mainScreen]
		? [NSScreen mainScreen].backingScaleFactor : 2.0;
	(void)scale;

	[view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];

	NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
									properties:@{}];

	[view removeFromSuperview];
	[offscreen close];
	return png;
}

static int bridge_render_to_png(lua_State *L) {
	NSView *view  = check_view(L, 1);
	CGFloat width  = luaL_optnumber(L, 2, 400);
	CGFloat height = luaL_optnumber(L, 3, 300);
	view.frame = NSMakeRect(0, 0, width, height);
	layout_recursive(view, width);
	NSData *png = offscreen_render(view, width, height);
	if (!png) { lua_pushnil(L); return 1; }
	lua_pushlstring(L, png.bytes, png.length);
	return 1;
}

#pragma mark - File watcher

static NSMutableDictionary *gFileWatchers = nil;

typedef struct {
	FSEventStreamRef stream;
	int luaRef;
} FileWatcherEntry;

static void file_watcher_callback(ConstFSEventStreamRef streamRef,
	void *clientCallBackInfo, size_t numEvents, void *eventPaths,
	const FSEventStreamEventFlags *eventFlags,
	const FSEventStreamEventId *eventIds)
{
	(void)streamRef; (void)numEvents; (void)eventPaths;
	(void)eventFlags; (void)eventIds;
	NSValue *boxed = (__bridge NSValue *)clientCallBackInfo;
	NSString *path = (__bridge NSString *)(void *)boxed.pointerValue;

	NSValue *entryBox = gFileWatchers[path];
	if (!entryBox || !gL) return;

	FileWatcherEntry entry;
	[entryBox getValue:&entry];
	if (entry.luaRef == LUA_NOREF) return;

	lua_rawgeti(gL, LUA_REGISTRYINDEX, entry.luaRef);
	lua_pushstring(gL, path.UTF8String);
	if (lua_pcall(gL, 1, 0, 0) != LUA_OK) {
		report_lua_error(gL, "watchFile");
		lua_pop(gL, 1);
	}
}

static int bridge_watch_file(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSString *path = [NSString stringWithUTF8String:pathC];

	if (!gFileWatchers) {
		gFileWatchers = [NSMutableDictionary dictionary];
	}

	/* Cancel any existing watcher for this path. */
	NSValue *existing = gFileWatchers[path];
	if (existing) {
		FileWatcherEntry old;
		[existing getValue:&old];
		FSEventStreamStop(old.stream);
		FSEventStreamInvalidate(old.stream);
		FSEventStreamRelease(old.stream);
		if (old.luaRef != LUA_NOREF) {
			luaL_unref(gL, LUA_REGISTRYINDEX, old.luaRef);
		}
		[gFileWatchers removeObjectForKey:path];
	}

	/* nil callback = just cancel */
	if (lua_isnoneornil(L, 2)) return 0;

	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	/* Use the path NSString pointer as stable context; kept alive by dict. */
	FSEventStreamContext ctx = {
		.version = 0,
		.info = (__bridge void *)([NSValue valueWithPointer:(__bridge void *)path]),
		.retain = NULL,
		.release = NULL,
		.copyDescription = NULL,
	};

	CFArrayRef paths = (__bridge CFArrayRef)@[path];
	FSEventStreamRef stream = FSEventStreamCreate(
		NULL, file_watcher_callback, &ctx,
		paths, kFSEventStreamEventIdSinceNow, 0.2,
		kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
	FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
	FSEventStreamStart(stream);

	FileWatcherEntry entry = { .stream = stream, .luaRef = ref };
	[gFileWatchers setObject:[NSValue value:&entry
							withObjCType:@encode(FileWatcherEntry)]
					  forKey:path];
	return 0;
}

static int bridge_pick_folder(lua_State *L) {
	const char *titleC = luaL_optstring(L, 1, "Open Folder");
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = NO;
	panel.canChooseDirectories = YES;
	panel.allowsMultipleSelection = NO;
	panel.canCreateDirectories = YES;
	panel.title = [NSString stringWithUTF8String:titleC];

	NSInteger response = [panel runModal];
	if (response != NSModalResponseOK || panel.URL == nil) {
		lua_pushnil(L);
		return 1;
	}

	lua_pushstring(L, panel.URL.path.UTF8String);
	return 1;
}

static int bridge_pick_file(lua_State *L) {
	const char *titleC = luaL_optstring(L, 1, "Open File");
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.canCreateDirectories = NO;
	panel.title = [NSString stringWithUTF8String:titleC];

	NSInteger response = [panel runModal];
	if (response != NSModalResponseOK || panel.URL == nil) {
		lua_pushnil(L);
		return 1;
	}

	lua_pushstring(L, panel.URL.path.UTF8String);
	return 1;
}

#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
	{"_window",           bridge_window},
	{"_vstack",           bridge_vstack},
	{"_hstack",           bridge_hstack},
	{"_hsplit",           bridge_hsplit},
	{"_vsplit",           bridge_vsplit},
	{"_separator",        bridge_separator},
	{"_spacer",           bridge_spacer},
	{"_image",            bridge_image},
	{"_imageViewer",      bridge_image_viewer},
	{"_systemImage",      bridge_system_image},
	{"_systemColor",      bridge_system_color},
	{"_add",              bridge_add},
	{"_layout",           bridge_layout},
	{"_viewSize",         bridge_view_size},
	{"_setContentSize", bridge_set_content_size},
	{"_setWindowMinSize", bridge_set_window_min_size},
	{"_setAppearance",    bridge_set_appearance},
	{"_tableview",        bridge_tableview},
	{"_toolbar_item",     bridge_toolbar_item},
	{"_button",           bridge_button},
	{"_actionButton",     bridge_action_button},
	{"_toggle",           bridge_toggle},
	{"_timerAfter",      bridge_timer_after},
	{"_show",             bridge_show},
	{"_create",           bridge_create},
	{"_font",             bridge_font},
	{"_perform",          bridge_perform},
	{"_callback",         bridge_callback},
	{"_httpGet",         bridge_http_get},
	{"_jsonParse",       bridge_json_parse},
	{"_tableSetRefresh", bridge_table_set_refresh},
	{"_textView",         bridge_text_view},
	{"_textViewGetText",  bridge_text_view_get_text},
	{"_textViewSetText",  bridge_text_view_set_text},
	{"_textViewOnChange", bridge_text_view_on_change},
	{"_textViewSetLanguage", bridge_text_view_set_language},
	{"_textViewSetWrapMode", bridge_text_view_set_wrap_mode},
	{"_symbolToggle",       bridge_symbol_toggle},
	{"_eval",             bridge_eval},
	{"_clearContainer",   bridge_clear_container},
	{"_renderToPNG",      bridge_render_to_png},
	{"_watchFile",        bridge_watch_file},
	{"_pickFolder",       bridge_pick_folder},
	{"_pickFile",         bridge_pick_file},
	{"_outlineview",      bridge_outlineview},
	{"_listDirectory",    bridge_list_directory},
	{NULL, NULL},
};

static void register_metatable(lua_State *L, const char *name) {
	luaL_newmetatable(L, name);
	lua_pushcfunction(L, gc_objc);
	lua_setfield(L, -2, "__gc");
	lua_pushcfunction(L, nsview_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, nsview_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

int luaopen_bridge(lua_State *L) {
	register_metatable(L, "nsview");
	register_metatable(L, "nswindow");
	register_metatable(L, "nsobject");
	luaL_newlib(L, bridge_lib);
	return 1;
}

#pragma mark - Main

/*
 * The executable is intentionally a tiny loader. AppKit.dylib owns the host
 * runtime as well as luaopen_AppKit, so the same image that Lua requires also
 * owns every AppKit control, layout key, callback target, and canvas service.
 */
int lua_objc_main(int argc, char *argv[]) {
	[NSApplication sharedApplication];

	const char *appearance = NULL;
	const char *script = NULL;
	int preview_mode = 0;
	CGFloat preview_width = 400;
	CGFloat preview_height = 300;
	const char *preview_out = NULL;
	const char *script_args[256];
	int script_arg_count = 0;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--preview") == 0) {
			preview_mode = 1;
		} else if (strncmp(argv[i], "--width=", 8) == 0) {
			preview_width = atof(argv[i] + 8);
		} else if (strncmp(argv[i], "--height=", 9) == 0) {
			preview_height = atof(argv[i] + 9);
		} else if (strncmp(argv[i], "--out=", 6) == 0) {
			preview_out = argv[i] + 6;
		} else if (strncmp(argv[i], "--appearance=", 13) == 0) {
			appearance = argv[i] + 13;
		} else if (strcmp(argv[i], "--appearance") == 0 && i + 1 < argc) {
			appearance = argv[++i];
		} else if (argv[i][0] != '-') {
			if (!script) {
				script = argv[i];
			} else if (script_arg_count < (int)(sizeof(script_args) / sizeof(script_args[0]))) {
				script_args[script_arg_count++] = argv[i];
			}
		}
	}

	if (!script) script = "examples/hello.lua";

	lua_State *L = luaL_newstate();
	gL = L;
	luaL_openlibs(L);

	LuaStateOwner *mainOwner = [[LuaStateOwner alloc] initWithState:L];
	(void)mainOwner;  /* released by ARC at return → -dealloc → lua_close */

	luaL_requiref(L, "AppKitNative", luaopen_bridge, 1);
	lua_pop(L, 1);
	/* Compatibility for application code that still imports the old private
	 * name directly. Public framework code uses AppKitNative. */
	luaL_requiref(L, "bridge", luaopen_bridge, 1);
	lua_pop(L, 1);

	if (appearance && strcmp(appearance, "system") != 0) {
		lua_pushstring(L, appearance);
		lua_setglobal(L, "_LAUNCH_APPEARANCE");
	}

	lua_newtable(L);
	if (script) {
		lua_pushinteger(L, 0);
		lua_pushstring(L, script);
		lua_settable(L, -3);
	}
	for (int i = 0; i < script_arg_count; i++) {
		lua_pushinteger(L, i + 1);
		lua_pushstring(L, script_args[i]);
		lua_settable(L, -3);
	}
	lua_setglobal(L, "arg");

	char cwd[4096];
	if (getcwd(cwd, sizeof(cwd))) {
		char frameworkDirectory[PATH_MAX] = "";
		Dl_info imageInfo;
		if (dladdr((const void *)&lua_objc_main, &imageInfo)
			&& imageInfo.dli_fname) {
			char imagePath[PATH_MAX];
			snprintf(imagePath, sizeof(imagePath), "%s", imageInfo.dli_fname);
			snprintf(frameworkDirectory, sizeof(frameworkDirectory), "%s",
				dirname(imagePath));
		}

		lua_getglobal(L, "package");
		lua_getfield(L, -1, "path");
		const char *defpath = lua_tostring(L, -1);
		char newpath[8192];
		snprintf(newpath, sizeof(newpath), "%s;%s/?.lua;%s/lua/?.lua", defpath, cwd, cwd);
		lua_pushstring(L, newpath);
		lua_setfield(L, -3, "path");
		lua_pop(L, 1);

		lua_getfield(L, -1, "cpath");
		const char *defcpath = lua_tostring(L, -1);
		char newcpath[8192];
		snprintf(newcpath, sizeof(newcpath), "%s;%s/build/?.dylib;%s/?.dylib",
			defcpath, cwd, frameworkDirectory);
		lua_pushstring(L, newcpath);
		lua_setfield(L, -3, "cpath");
		lua_pop(L, 2);
	}

	if (preview_mode) {
		/* --preview: eval the script in canvas mode, render to PNG, write out. */
		lua_State *C = canvas_state_create();
		if (!C) {
			fprintf(stderr, "preview: failed to create canvas state\n");
			return 1;
		}

	/* Read the file into a string so we can pass it through bridge_eval's
		 * canvas wrapper (which intercepts ns.Window → ns.VStack). */
		FILE *fp = fopen(script, "r");
		if (!fp) {
			fprintf(stderr, "preview: cannot open %s\n", script);
			lua_close(C);
			return 1;
		}
		fseek(fp, 0, SEEK_END);
		long fsize = ftell(fp);
		rewind(fp);
		char *code = malloc((size_t)fsize + 1);
		fread(code, 1, (size_t)fsize, fp);
		code[fsize] = '\0';
		fclose(fp);

		char *wrapped = malloc((size_t)fsize + 256);
		snprintf(wrapped, (size_t)fsize + 256,
			"local ns=require('AppKit');"
			"local __rr;"
			"ns.Window=function(p) __rr=ns.VStack(p) return __rr end;"
			"ns.Preview=function(p) __rr=ns.VStack(p) return __rr end;"
			"local __rok,__ret=pcall(function()\n%s\nend);"
			"if not __rok then error(__ret) end;"
			"return __ret or __rr",
			code);
		free(code);

		if (luaL_loadstring(C, wrapped) != LUA_OK ||
			lua_pcall(C, 0, 1, 0) != LUA_OK) {
			report_lua_error(C, "preview");
			free(wrapped);
			lua_close(C);
			return 1;
		}
		free(wrapped);

		id resultObj = nil;
		ObjCRef *ref = luaL_testudata(C, -1, "nsview");
		if (!ref) ref = luaL_testudata(C, -1, "nswindow");
		if (ref) resultObj = (__bridge id)ref->ptr;

		if (!resultObj || ![resultObj isKindOfClass:[NSView class]]) {
			fprintf(stderr, "preview: script did not return a view\n");
			lua_close(C);
			return 1;
		}

		NSView *view = (NSView *)resultObj;
		view.frame = NSMakeRect(0, 0, preview_width, preview_height);
		layout_recursive(view, preview_width);

		NSData *png = offscreen_render(view, preview_width, preview_height);
		lua_close(C);

		if (!png) {
			fprintf(stderr, "preview: render failed\n");
			return 1;
		}

		int write_ok = 0;
		if (!preview_out || strcmp(preview_out, "-") == 0) {
			write_ok = fwrite(png.bytes, 1, png.length, stdout) == (size_t)png.length;
		} else {
			FILE *out = fopen(preview_out, "wb");
			if (out) {
				write_ok = fwrite(png.bytes, 1, png.length, out) == (size_t)png.length;
				fclose(out);
			}
		}

		return write_ok ? 0 : 1;
	}

	if (luaL_dofile(L, script) != LUA_OK) {
		report_lua_error(L, "script");
		return 1;
	}

	[NSApp run];

	return 0;
}
