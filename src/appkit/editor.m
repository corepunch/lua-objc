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

	NSFontWeight w = weightStr
		? lookupFontWeight([NSString stringWithUTF8String:weightStr])
		: NSFontWeightRegular;

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

	NSTextView *tv = [[NSTextView alloc]
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
	/* Suppress NSTextDidChangeNotification for programmatic updates so that
	 * the IDE change handler only fires for user-initiated edits. */
	objc_setAssociatedObject(tv, &kKeys[kTextProgrammaticKey], @YES,
		OBJC_ASSOCIATION_RETAIN);
	tv.string = [NSString stringWithUTF8String:str];
	objc_setAssociatedObject(tv, &kKeys[kTextProgrammaticKey], nil,
		OBJC_ASSOCIATION_RETAIN);
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
