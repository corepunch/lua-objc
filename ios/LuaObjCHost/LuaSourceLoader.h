#import <Foundation/Foundation.h>

@interface LuaSourceLoader : NSObject
@property (nonatomic, copy) NSURL *baseURL;
+ (instancetype)shared;
- (BOOL)ping:(NSError **)error;
- (NSData *)dataForPath:(NSString *)rel error:(NSError **)error;
- (NSString *)sourceForModule:(NSString *)name error:(NSError **)error;
- (NSString *)entryPath:(NSError **)error;
- (void)dropCacheForPath:(NSString *)rel;
@end
