#import <AppKit/AppKit.h>

// Text only. No keyboard injection, network listener, or clipboard logging.
@interface OhmansyClipboardBridge : NSObject
- (instancetype)initWithSocket:(NSString *)path;
- (void)start;
@end
