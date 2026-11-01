#import <MetalKit/MetalKit.h>

@interface WelcomeCanvas : MTKView <MTKViewDelegate>
- (instancetype)initWithFrame:(NSRect)frame;
- (void)setAnimating:(BOOL)animating;
@end
