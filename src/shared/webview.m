#pragma mark - WebView

/* WKWebView for SwiftUI's WebView, on AppKit and UIKit. Navigation state
 * (URL, title, progress, back/forward) and loading and error events go to
 * one Lua callback as (event, value); lua/ui/webpage.lua turns them into an
 * observable WebPage and sends actions back through _webViewAction. */

#import <WebKit/WebKit.h>

@interface LuaWebView : WKWebView <WKNavigationDelegate>
@property(nonatomic, strong) LuaReg *stateCallback;
@end

/* Calls `reg` with the values `push` leaves on its stack. */
static void webview_call(LuaReg *reg, int count, const char *context, void (^push)(lua_State *L)) {
	if (!reg || !lua_reg_push(reg)) return;
	lua_State *L = reg.owner.L;
	push(L);
	if (lua_pcall(L, count, 0, 0) != LUA_OK) report_lua_error(L, context);
}

@implementation LuaWebView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self addObserver:self forKeyPath:@"estimatedProgress"
		options:NSKeyValueObservingOptionNew context:NULL];
	return self;
}
- (void)dealloc { [self removeObserver:self forKeyPath:@"estimatedProgress"]; }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
	if ([keyPath isEqualToString:@"estimatedProgress"]) { [self publishState]; return; }
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)publishState {
	webview_call(self.stateCallback, 2, "WebView state callback", ^(lua_State *L) {
		lua_pushliteral(L, "state");
		lua_newtable(L);
		lua_pushstring(L, self.URL.absoluteString.UTF8String ?: ""); lua_setfield(L, -2, "url");
		lua_pushstring(L, self.title.UTF8String ?: ""); lua_setfield(L, -2, "title");
		lua_pushnumber(L, self.estimatedProgress); lua_setfield(L, -2, "progress");
		lua_pushboolean(L, self.canGoBack); lua_setfield(L, -2, "canGoBack");
		lua_pushboolean(L, self.canGoForward); lua_setfield(L, -2, "canGoForward");
	});
}
- (void)publishLoading:(BOOL)loading {
	webview_call(self.stateCallback, 2, "WebView state callback", ^(lua_State *L) {
		lua_pushliteral(L, "loading");
		lua_pushboolean(L, loading);
	});
}
- (void)webView:(__unused WKWebView *)webView didStartProvisionalNavigation:(__unused WKNavigation *)navigation {
	[self publishLoading:YES];
}
- (void)webView:(__unused WKWebView *)webView didCommitNavigation:(__unused WKNavigation *)navigation {
	[self publishState];
}
- (void)webView:(__unused WKWebView *)webView didFinishNavigation:(__unused WKNavigation *)navigation {
	[self publishState];
	[self publishLoading:NO];
}
- (void)webView:(__unused WKWebView *)webView didFailNavigation:(__unused WKNavigation *)navigation withError:(NSError *)error {
	[self publishState];
	webview_call(self.stateCallback, 2, "WebView state callback", ^(lua_State *L) {
		lua_pushliteral(L, "error");
		lua_pushstring(L, error.localizedDescription.UTF8String ?: "Web page failed");
	});
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self webView:webView didFailNavigation:navigation withError:error];
}
@end

// _webView(url, onState) -> view
static int bridge_webview(lua_State *L) {
	const char *url = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	LuaWebView *view = [[LuaWebView alloc] initWithFrame:CGRectZero];
	view.stateCallback = lua_reg_create(L, 2, YES);
	view.navigationDelegate = view;
	NSURL *URL = [NSURL URLWithString:@(url)];
	if (URL) [view loadRequest:[NSURLRequest requestWithURL:URL]];
#if TARGET_OS_IPHONE
	push_objc(L, view, "uiview");
#else
	push_objc(L, view, "nsview");
#endif
	return 1;
}

// _webViewAction(view, action, ...): back, forward, reload, stop, load(url),
// evaluateJavaScript(script, callback), find(query, backwards, caseSensitive,
// wraps, callback), setPageZoom(zoom), hideBackground and, on the Mac,
// setMagnification(scale) and allowsMagnification(enabled). iOS has no
// magnification control, so the latter is ignored there.
static int bridge_webview_action(lua_State *L) {
	LuaWebView *view = lua_objc_check_object(L, 1, [LuaWebView class], "WebView");
	const char *action = luaL_checkstring(L, 2);
	if (strcmp(action, "back") == 0) [view goBack];
	else if (strcmp(action, "forward") == 0) [view goForward];
	else if (strcmp(action, "reload") == 0) [view reload];
	else if (strcmp(action, "stop") == 0) [view stopLoading];
	else if (strcmp(action, "load") == 0) {
		NSURL *url = [NSURL URLWithString:@(luaL_checkstring(L, 3))];
		if (url) [view loadRequest:[NSURLRequest requestWithURL:url]];
	} else if (strcmp(action, "evaluateJavaScript") == 0) {
		NSString *script = @(luaL_checkstring(L, 3));
		LuaReg *callback = lua_isfunction(L, 4) ? lua_reg_create(L, 4, YES) : nil;
		[view evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
			webview_call(callback, 2, "WebView JavaScript callback", ^(lua_State *state) {
				if (error) { lua_pushnil(state); lua_pushstring(state, error.localizedDescription.UTF8String ?: "JavaScript failed"); }
				else if ([result isKindOfClass:[NSString class]]) { lua_pushstring(state, [result UTF8String]); lua_pushnil(state); }
				else if ([result isKindOfClass:[NSNumber class]]) { lua_pushnumber(state, [result doubleValue]); lua_pushnil(state); }
				else { lua_pushnil(state); lua_pushnil(state); }
			});
		}];
	} else if (strcmp(action, "find") == 0) {
		NSString *query = @(luaL_checkstring(L, 3));
		WKFindConfiguration *config = [[WKFindConfiguration alloc] init];
		config.backwards = lua_toboolean(L, 4);
		config.caseSensitive = lua_toboolean(L, 5);
		config.wraps = lua_toboolean(L, 6);
		LuaReg *callback = lua_isfunction(L, 7) ? lua_reg_create(L, 7, YES) : nil;
		[view findString:query withConfiguration:config completionHandler:^(WKFindResult *result) {
			webview_call(callback, 1, "WebView find callback", ^(lua_State *state) {
				lua_pushboolean(state, result.matchFound);
			});
		}];
	} else if (strcmp(action, "setPageZoom") == 0) {
		CGFloat zoom = (CGFloat)luaL_checknumber(L, 3);
		if (zoom <= 0) return luaL_error(L, "page zoom must be positive");
		view.pageZoom = zoom;
	} else if (strcmp(action, "hideBackground") == 0) {
		// The page's own background shows through to the window's.
#if TARGET_OS_IPHONE
		view.opaque = NO;
		view.backgroundColor = UIColor.clearColor;
		view.scrollView.backgroundColor = UIColor.clearColor;
#else
		view.underPageBackgroundColor = NSColor.clearColor;
#endif
	} else if (strcmp(action, "allowsMagnification") == 0) {
#if !TARGET_OS_IPHONE
		view.allowsMagnification = lua_toboolean(L, 3);
#endif
#if !TARGET_OS_IPHONE
	} else if (strcmp(action, "setMagnification") == 0) {
		CGFloat scale = (CGFloat)luaL_checknumber(L, 3);
		if (scale <= 0) return luaL_error(L, "magnification must be positive");
		view.allowsMagnification = YES;
		view.magnification = scale;
#endif
	} else return luaL_error(L, "unknown WebView action: %s", action);
	return 0;
}

#define LUA_OBJC_WEBVIEW_FUNCTIONS \
	{"_webView", bridge_webview}, \
	{"_webViewAction", bridge_webview_action},
