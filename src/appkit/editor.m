#pragma mark - Show

static int bridge_NSWindow_show_impl(lua_State *L) {
	NSWindow *w = (__bridge NSWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[NSApp unhide:nil];
	[NSApp activate];
	[w makeKeyAndOrderFront:nil];
	[w makeKeyWindow];
	[w makeMainWindow];
	[w orderFrontRegardless];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
		[NSApp unhide:nil];
		[NSApp activate];
		[w makeKeyAndOrderFront:nil];
		[w makeKeyWindow];
		[w makeMainWindow];
		[w orderFrontRegardless];
	});

	return 0;
}

#pragma mark - Generic bridge (_font)

static int bridge_font(lua_State *L) {
	CGFloat size = luaL_checknumber(L, 1);
	const char *weightStr = luaL_optstring(L, 2, NULL);

	NSFontWeight w = weightStr
		? lookupFontWeight([NSString stringWithUTF8String:weightStr])
		: NSFontWeightRegular;

	NSFont *font = [NSFont systemFontOfSize:size weight:w];
	push_objc(L, font, "nsobject");
	return 1;
}

#include "syntax_highlight.m"

#pragma mark - NSTextView (code editor)

@interface LuaTextScrollView : NSScrollView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *language;
@property(nonatomic) BOOL wrapMode;
@end

@implementation LuaTextScrollView
- (NSString *)text {
	return ((NSTextView *)self.documentView).string;
}
- (void)setText:(NSString *)value {
	NSTextView *textView = (NSTextView *)self.documentView;
	objc_setAssociatedObject(textView, &kKeys[kTextProgrammaticKey], @YES,
		OBJC_ASSOCIATION_RETAIN);
	textView.string = value ?: @"";
	objc_setAssociatedObject(textView, &kKeys[kTextProgrammaticKey], nil,
		OBJC_ASSOCIATION_RETAIN);
}
- (NSString *)language {
	SyntaxTextStorage *storage =
		(SyntaxTextStorage *)((NSTextView *)self.documentView).textStorage;
	return [storage isKindOfClass:[SyntaxTextStorage class]]
		? storage.language : @"";
}
- (void)setLanguage:(NSString *)value {
	SyntaxTextStorage *storage =
		(SyntaxTextStorage *)((NSTextView *)self.documentView).textStorage;
	if ([storage isKindOfClass:[SyntaxTextStorage class]]) {
		storage.language = value ?: @"";
	}
}
- (BOOL)wrapMode {
	return [objc_getAssociatedObject(
		self, &kKeys[kTextWrapKey]) boolValue];
}
- (void)setWrapMode:(BOOL)wrap {
	NSTextView *textView = (NSTextView *)self.documentView;
	NSTextContainer *container = textView.textContainer;
	textView.horizontallyResizable = !wrap;
	container.widthTracksTextView = wrap;
	container.containerSize = wrap
		? NSMakeSize(self.contentSize.width, FLT_MAX)
		: NSMakeSize(FLT_MAX, FLT_MAX);
	self.hasHorizontalScroller = !wrap;
	objc_setAssociatedObject(self, &kKeys[kTextWrapKey], @(wrap),
		OBJC_ASSOCIATION_RETAIN);
}
@end

static int bridge_text_view(lua_State *L) {
	NSScrollView *sv = [[LuaTextScrollView alloc]
		initWithFrame:NSMakeRect(0, 0, kEditorDefaultWidth, kEditorDefaultHeight)];
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

	NSTextView *tv = [[LuaNativeTextView alloc]
		initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)
		textContainer:tc];
	tv.font = [NSFont monospacedSystemFontOfSize:kEditorFontSize
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
	/* Sentinel used by TextView method dispatch. */
	objc_setAssociatedObject(sv, &kKeys[kTextViewSourceKey], @YES, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, sv, "nsview");
	return 1;
}

static int bridge_NSScrollView_onChange_impl(lua_State *L) {
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
		if (objc_getAssociatedObject(note.object, &kKeys[kTextProgrammaticKey])) return;
		NSNumber *refNum = objc_getAssociatedObject(note.object,
			&kKeys[kTextChangeKey]);
		if (!refNum || !owner) return;
		lua_State *callL = owner.L;
		if (!callL) return;
		lua_rawgeti(callL, LUA_REGISTRYINDEX, refNum.intValue);
		lua_pushstring(callL,
			((NSTextView *)note.object).string.UTF8String);
		lua_objc_pcall(callL, 1, 0, "text change");
	}];

	return 0;
}

/* Symbol button: a non-toggling NSButton with an SF Symbol, matching the
 * visual style of _symbolToggle (rounded bezel, same size and point weight).
 * Args: symbolName, tooltip */
static int bridge_symbol_button(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *tooltip = luaL_optstring(L, 2, "");

	NSString *name = [NSString stringWithUTF8String:symbol];
	NSImage *img = [NSImage imageWithSystemSymbolName:name
		accessibilityDescription:[NSString stringWithUTF8String:tooltip]];
	if (!img) {
		return luaL_error(L, "unknown SF Symbol: %s", symbol);
	}

	NSImageSymbolConfiguration *config =
		[NSImageSymbolConfiguration configurationWithPointSize:kSymbolTogglePointSize
														weight:NSFontWeightMedium];
	img = [img imageWithSymbolConfiguration:config];

	NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kSymbolToggleSize, kSymbolToggleSize)];
	btn.title = @"";
	btn.image = img;
	btn.imagePosition = NSImageOnly;
	btn.bezelStyle = NSBezelStyleRounded;
	btn.buttonType = NSButtonTypeMomentaryPushIn;
	btn.toolTip = [NSString stringWithUTF8String:tooltip];
	btn.accessibilityLabel = btn.toolTip;

	push_objc(L, btn, "nsview");
	return 1;
}

/* Symbol toggle: an NSButton with an SF Symbol, acting as an on/off toggle.
 * Args: symbolName, tooltip, initialState, callback(optional) */
static int bridge_symbol_toggle(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *tooltip = luaL_optstring(L, 2, "");
	int state = lua_toboolean(L, 3);
	int ref;
	LUA_OPT_CALLBACK_REF(L, 4, ref);

	NSString *name = [NSString stringWithUTF8String:symbol];
	NSImage *img = [NSImage imageWithSystemSymbolName:name
		accessibilityDescription:[NSString stringWithUTF8String:tooltip]];
	if (!img) {
		if (ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, ref);
		return luaL_error(L, "unknown SF Symbol: %s", symbol);
	}

	NSImageSymbolConfiguration *config =
		[NSImageSymbolConfiguration configurationWithPointSize:kSymbolTogglePointSize
														weight:NSFontWeightMedium];
	img = [img imageWithSymbolConfiguration:config];

	NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kSymbolToggleSize, kSymbolToggleSize)];
	btn.title = @"";
	btn.image = img;
	btn.imagePosition = NSImageOnly;
	btn.bezelStyle = NSBezelStyleRounded;
	btn.buttonType = NSButtonTypeOnOff;
	btn.state = state ? NSControlStateValueOn : NSControlStateValueOff;
	btn.toolTip = [NSString stringWithUTF8String:tooltip];
	btn.accessibilityLabel = btn.toolTip;

	if (ref != LUA_NOREF) {
		objc_setAssociatedObject(btn, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		btn.target = [LuaButtonTarget shared];
		btn.action = @selector(onAction:);
	}

	push_objc(L, btn, "nsview");
	return 1;
}

#include "canvas_eval.m"
