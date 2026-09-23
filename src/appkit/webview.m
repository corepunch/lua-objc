#import <WebKit/WebKit.h>

@interface LuaWebView : WKWebView <WKNavigationDelegate>
@property (nonatomic, strong) LuaReg *stateCallback;
@end

@implementation LuaWebView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self addObserver:self forKeyPath:@"estimatedProgress"
		options:NSKeyValueObservingOptionNew context:NULL];
	return self;
}
- (void)dealloc {
	[self removeObserver:self forKeyPath:@"estimatedProgress"];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if ([keyPath isEqualToString:@"estimatedProgress"]) { [self publishState]; return; }
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self webView:webView didFailNavigation:navigation withError:error];
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
	if (self.stateCallback && lua_reg_push(self.stateCallback)) {
		lua_State *L = self.stateCallback.owner.L;
		lua_pushliteral(L, "loading"); lua_pushboolean(L, 1);
		if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
	}
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
	[self publishState];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	[self publishState];
	if (self.stateCallback && lua_reg_push(self.stateCallback)) {
		lua_State *L = self.stateCallback.owner.L;
		lua_pushliteral(L, "loading"); lua_pushboolean(L, 0);
		if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
	}
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self publishState];
	if (self.stateCallback && lua_reg_push(self.stateCallback)) {
		lua_State *L = self.stateCallback.owner.L;
		lua_pushliteral(L, "error"); lua_pushstring(L, error.localizedDescription.UTF8String ?: "Web page failed");
		if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
	}
}
- (void)publishState {
	LuaReg *reg = self.stateCallback;
	if (!reg || !lua_reg_push(reg)) return;
	lua_State *L = reg.owner.L;
	lua_pushliteral(L, "state");
	lua_newtable(L);
	lua_pushstring(L, self.URL.absoluteString.UTF8String ?: ""); lua_setfield(L, -2, "url");
	lua_pushstring(L, self.title.UTF8String ?: ""); lua_setfield(L, -2, "title");
	lua_pushnumber(L, self.estimatedProgress); lua_setfield(L, -2, "progress");
	lua_pushboolean(L, self.canGoBack); lua_setfield(L, -2, "canGoBack");
	lua_pushboolean(L, self.canGoForward); lua_setfield(L, -2, "canGoForward");
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
}
@end

static int bridge_webview(lua_State *L) {
	const char *url = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	LuaWebView *view = [[LuaWebView alloc] initWithFrame:NSZeroRect];
	view.stateCallback = lua_reg_create(L, 2, YES);
	view.navigationDelegate = view;
	NSURL *URL = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
	if (URL) [view loadRequest:[NSURLRequest requestWithURL:URL]];
	push_objc(L, view, "nsview");
	return 1;
}

static int bridge_webview_action(lua_State *L) {
	LuaWebView *view = (LuaWebView *)lua_objc_check_object(L, 1, [LuaWebView class], "WebView");
	const char *action = luaL_checkstring(L, 2);
	if (strcmp(action, "back") == 0) [view goBack];
	else if (strcmp(action, "forward") == 0) [view goForward];
	else if (strcmp(action, "reload") == 0) [view reload];
	else if (strcmp(action, "stop") == 0) [view stopLoading];
	else if (strcmp(action, "load") == 0) {
		NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:luaL_checkstring(L, 3)]];
		if (url) [view loadRequest:[NSURLRequest requestWithURL:url]];
	} else if (strcmp(action, "evaluateJavaScript") == 0) {
		const char *script = luaL_checkstring(L, 3);
		LuaReg *callback = lua_isfunction(L, 4) ? lua_reg_create(L, 4, YES) : nil;
		[view evaluateJavaScript:[NSString stringWithUTF8String:script] completionHandler:^(id result, NSError *error) {
			if (!callback || !lua_reg_push(callback)) return;
			lua_State *state = callback.owner.L;
			if (error) { lua_pushnil(state); lua_pushstring(state, error.localizedDescription.UTF8String ?: "JavaScript failed"); }
			else if ([result isKindOfClass:[NSString class]]) { lua_pushstring(state, [result UTF8String]); lua_pushnil(state); }
			else if ([result isKindOfClass:[NSNumber class]]) { lua_pushnumber(state, [result doubleValue]); lua_pushnil(state); }
			else { lua_pushnil(state); lua_pushnil(state); }
			if (lua_pcall(state, 2, 0, 0) != LUA_OK) report_lua_error(state, "WebView JavaScript callback");
		}];
	} else return luaL_error(L, "unknown WebView action: %s", action);
	return 0;
}
