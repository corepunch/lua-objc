#import <Foundation/Foundation.h>

typedef void (^LuaHotHandler)(NSDictionary *event);

@interface LuaHotClient : NSObject
@property (nonatomic, copy) LuaHotHandler handler;
- (void)connectToURL:(NSURL *)url;
- (void)disconnect;
@end
