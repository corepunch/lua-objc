#import <Foundation/Foundation.h>
#import <dlfcn.h>
struct DirStats { uint64_t values[5]; };
@interface NSObject (DirStats)
+ (int)getDirStatInfoForPath:(NSString *)path orFD:(int)fd withOptions:(long long)options info:(struct DirStats *)info;
+ (BOOL)isSDHierarchyEnabledForPath:(NSString *)path orFD:(int)fd;
@end
int main(){@autoreleasepool{
	dlopen("/System/Library/PrivateFrameworks/SpaceAttribution.framework/SpaceAttribution",RTLD_NOW);
	Class cls=NSClassFromString(@"SASupport");
	for(NSString *path in @[@"/Applications",NSHomeDirectory(),[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Developer"],@"/System/Volumes/Data"]){
	struct DirStats info={0}; int r=[cls getDirStatInfoForPath:path orFD:-1 withOptions:0 info:&info];
	NSLog(@"%@ status=%d enabled=%d values=%llu,%llu,%llu,%llu,%llu",path,r,[cls isSDHierarchyEnabledForPath:path orFD:-1],info.values[0],info.values[1],info.values[2],info.values[3],info.values[4]);
	}
}}
