#import "LuaObjCHost.h"

@implementation LuaSourceLoader {
	NSURLSession *_session;
	NSMutableDictionary<NSString *, NSData *> *_cache;
}

+ (instancetype)shared {
	static LuaSourceLoader *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[self alloc] init]; });
	return shared;
}

- (instancetype)init {
	self = [super init];
	NSOperationQueue *queue = [NSOperationQueue new];
	queue.maxConcurrentOperationCount = 4;
	_session = [NSURLSession sessionWithConfiguration:
		NSURLSessionConfiguration.ephemeralSessionConfiguration
		delegate:nil delegateQueue:queue];
	_cache = [NSMutableDictionary dictionary];
	return self;
}

- (NSData *)GET:(NSString *)pathQuery error:(NSError **)error {
	NSURL *url = [NSURL URLWithString:pathQuery relativeToURL:self.baseURL];
	if (!url) {
		if (error) *error = [NSError errorWithDomain:@"LuaSourceLoader"
			code:1 userInfo:@{NSLocalizedDescriptionKey: @"bad url"}];
		return nil;
	}
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block NSData *body = nil;
	__block NSError *taskError = nil;
	__block NSInteger status = 0;
	NSURLSessionDataTask *task = [_session dataTaskWithURL:url
		completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
			taskError = err;
			body = data;
			if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
				status = [(NSHTTPURLResponse *)response statusCode];
			}
			dispatch_semaphore_signal(sem);
		}];
	[task resume];
	if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC))) {
		if (error) *error = [NSError errorWithDomain:@"LuaSourceLoader"
			code:2 userInfo:@{NSLocalizedDescriptionKey: @"packager timeout"}];
		return nil;
	}
	if (taskError) {
		if (error) *error = taskError;
		return nil;
	}
	if (status != 200) {
		if (error) *error = [NSError errorWithDomain:@"LuaSourceLoader"
			code:status
			userInfo:@{NSLocalizedDescriptionKey:
				[NSString stringWithFormat:@"HTTP %ld %@",
					(long)status, pathQuery]}];
		return nil;
	}
	return body;
}

- (BOOL)ping:(NSError **)error {
	NSError *err = nil;
	NSData *data = [self GET:@"/health" error:&err];
	if (!data) {
		if (error) *error = err;
		return NO;
	}
	return YES;
}

- (NSData *)dataForPath:(NSString *)rel error:(NSError **)error {
	@synchronized (_cache) {
		NSData *cached = _cache[rel];
		if (cached) return cached;
	}
	NSString *escaped = [rel stringByAddingPercentEncodingWithAllowedCharacters:
		[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSError *err = nil;
	NSData *data = [self GET:[NSString stringWithFormat:@"/file?path=%@", escaped]
		error:&err];
	if (!data) {
		if (error) *error = err;
		return nil;
	}
	@synchronized (_cache) { _cache[rel] = data; }
	return data;
}

- (NSString *)sourceForModule:(NSString *)name error:(NSError **)error {
	NSString *escaped = [name stringByAddingPercentEncodingWithAllowedCharacters:
		[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSError *err = nil;
	NSData *data = [self GET:[NSString stringWithFormat:@"/module?name=%@", escaped]
		error:&err];
	if (!data) {
		if (error) *error = err;
		return nil;
	}
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)entryPath:(NSError **)error {
	NSError *err = nil;
	NSData *data = [self GET:@"/entry" error:&err];
	if (!data) {
		if (error) *error = err;
		return nil;
	}
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
	if (![json isKindOfClass:[NSDictionary class]]) {
		if (error) *error = err;
		return nil;
	}
	return json[@"path"];
}

- (void)dropCacheForPath:(NSString *)rel {
	@synchronized (_cache) { [_cache removeObjectForKey:rel]; }
}
@end
