#import "LuaRuntime.h"

@implementation LRTReloadConnection {
	NSURL *_url;
	NSURLSession *_session;
	NSURLSessionWebSocketTask *_task;
	BOOL _stopped;
}

/* One session for the connection's life. Tasks are cancelled before a
 * replacement opens and the session is invalidated on disconnect: a
 * session never invalidated keeps its connection pool, delegate queue and
 * their Mach ports for the life of the process. */
- (void)connectToURL:(NSURL *)url {
	[_session invalidateAndCancel];
	_url = url;
	_stopped = NO;
	NSURLSessionConfiguration *config =
		NSURLSessionConfiguration.ephemeralSessionConfiguration;
	_session = [NSURLSession sessionWithConfiguration:config
		delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
	[self open];
}

- (void)disconnect {
	_stopped = YES;
	[_task cancel];
	_task = nil;
	[_session invalidateAndCancel];
	_session = nil;
}

- (void)open {
	if (_stopped || !_url) return;
	NSString *scheme = _url.scheme.lowercaseString;
	if (![scheme isEqualToString:@"ws"] && ![scheme isEqualToString:@"wss"]) {
		NSLog(@"[lua-objc] skip websocket; scheme=%@", _url.scheme);
		return;
	}
	[_task cancel];
	_task = [_session webSocketTaskWithURL:_url];
	[_task resume];
	[self receive];
}

- (void)receive {
	__weak typeof(self) weakSelf = self;
	NSURLSessionWebSocketTask *task = _task;
	[task receiveMessageWithCompletionHandler:^(
		NSURLSessionWebSocketMessage *message, NSError *error) {
		__strong typeof(weakSelf) self = weakSelf;
		// A cancelled task still completes; only the current task may reconnect.
		if (!self || self->_stopped || self->_task != task) return;
		if (error) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC),
				dispatch_get_main_queue(), ^{ [self open]; });
			return;
		}
		NSString *text = message.string;
		if (!text && message.data) {
			text = [[NSString alloc] initWithData:message.data
				encoding:NSUTF8StringEncoding];
		}
		if (text.length) {
			NSData *jsonData = [text dataUsingEncoding:NSUTF8StringEncoding];
			id obj = [NSJSONSerialization JSONObjectWithData:jsonData
				options:0 error:nil];
			if ([obj isKindOfClass:[NSDictionary class]] && self.handler) {
				self.handler(obj);
			}
		}
		[self receive];
	}];
}
@end
