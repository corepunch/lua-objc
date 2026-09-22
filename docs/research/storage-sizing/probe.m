#import <Foundation/Foundation.h>
#import <dlfcn.h>
@interface NSObject (StorageProbe)
+ (void)computeSizeOfVolumeAtURL:(NSURL *)url completionHandler:(void (^)(id,NSError *))handler;
- (void)startObservingWithUpdateHandler:(BOOL (^)(id,NSError *))handler;
- (void)startObservingURLs:(NSArray *)urls updateHandler:(BOOL (^)(id,NSError *))handler;
- (void)stopObserving;
@end
static void report(NSString *kind,id result,NSError *error, NSDate *start) {
	NSLog(@"%@ after %.3fs: class=%@ error=%@",kind,-start.timeIntervalSinceNow,[result class],error);
	NSArray *keys=[kind isEqual:@"volume"]?@[@"capacity",@"used",@"rawUsed",@"purgeableSize"]:[kind isEqual:@"urls"]?@[@"urlInfo",@"timeNow"]:@[@"time",@"status",@"diskUsed",@"rawSystemDataSize",@"appsDataInternal"];
	for(NSString *key in keys) { @try { id val=[result valueForKey:key]; if([val isKindOfClass:NSDictionary.class]) NSLog(@"%@ entries=%lu",key,(unsigned long)[val count]); else NSLog(@"%@=%@",key,val); } @catch(NSException *e) { NSLog(@"%@: %@",key,e.reason); } }
}
int main() { @autoreleasepool {
	dlopen("/System/Library/PrivateFrameworks/SpaceAttribution.framework/SpaceAttribution",RTLD_NOW);
	NSDate *start=NSDate.date;
	[NSClassFromString(@"SAVolumeSizer") computeSizeOfVolumeAtURL:[NSURL fileURLWithPath:@"/"] completionHandler:^(id r,NSError *e){report(@"volume",r,e,start);}];
	id app=[NSClassFromString(@"SAAppSizer") new];
	[app startObservingWithUpdateHandler:^BOOL(id r,NSError *e){report(@"apps",r,e,start);return YES;}];
	id urls=[NSClassFromString(@"SAURLSizer") new];
	[urls startObservingURLs:@[[NSURL fileURLWithPath:@"/Applications"]] updateHandler:^BOOL(id r,NSError *e){report(@"urls",r,e,start);return YES;}];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10]];
	[app stopObserving]; [urls stopObserving];
} }
