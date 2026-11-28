#pragma mark - AppKit HTML printing

#import <WebKit/WebKit.h>

/* The WebKit print operation must outlive the asynchronous load. Keep a
 * single job until the system panel returns; never open a browser or file. */
@interface LuaHTMLPrintJob : NSObject <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) WKNavigation *navigation;
@end

static LuaHTMLPrintJob *lua_appkit_print_job;

@implementation LuaHTMLPrintJob
- (void)webView:(__unused WKWebView *)webView
	decidePolicyForNavigationAction:(WKNavigationAction *)action
	decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
	NSString *scheme = action.request.URL.scheme.lowercaseString;
	decisionHandler(!scheme || [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"data"]
		? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(__unused WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	if (self != lua_appkit_print_job || navigation != self.navigation) return;
	self.navigation = nil;
	/* Run after WebKit's completion unwinds so its print snapshot can finish
	 * while AppKit is running the modal system panel. */
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self != lua_appkit_print_job) return;
		NSPrintInfo *info = [NSPrintInfo.sharedPrintInfo copy];
		NSPrintOperation *operation = [self.webView printOperationWithPrintInfo:info];
		operation.jobTitle = self.title;
		operation.showsPrintPanel = YES;
		operation.showsProgressPanel = YES;
		[operation runOperation];
		lua_appkit_print_job = nil;
	});
}

- (void)webView:(__unused WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	if (self != lua_appkit_print_job || navigation != self.navigation) return;
	NSLog(@"Could not prepare HTML printing: %@", error.localizedDescription);
	lua_appkit_print_job = nil;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self webView:webView didFailNavigation:navigation withError:error];
}

- (void)webViewWebContentProcessDidTerminate:(__unused WKWebView *)webView {
	if (self.navigation && self == lua_appkit_print_job) lua_appkit_print_job = nil;
}
@end

static int bridge_print_html(lua_State *L) {
	size_t length = 0;
	const char *bytes = luaL_checklstring(L, 1, &length);
	const char *title = luaL_optstring(L, 2, "Document");
	if (!NSThread.isMainThread || !NSApp.keyWindow || lua_appkit_print_job || !length || length > 4 * 1024 * 1024) {
		lua_pushboolean(L, NO);
		return 1;
	}
	NSString *html = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
	if (!html) {
		lua_pushboolean(L, NO);
		return 1;
	}
	LuaHTMLPrintJob *job = [LuaHTMLPrintJob new];
	job.title = [NSString stringWithUTF8String:title] ?: @"Document";
	WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
	configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
	configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
	job.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 612, 792) configuration:configuration];
	job.webView.navigationDelegate = job;
	lua_appkit_print_job = job;
	job.navigation = [job.webView loadHTMLString:html baseURL:nil];
	if (!job.navigation) lua_appkit_print_job = nil;
	lua_pushboolean(L, job.navigation != nil);
	return 1;
}
