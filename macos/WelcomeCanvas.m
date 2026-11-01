#import "WelcomeCanvas.h"
#import <QuartzCore/QuartzCore.h>

@interface WelcomeCanvas ()
@property(nonatomic, strong) id<MTLCommandQueue> commands;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic, strong) id<MTLRenderPipelineState> ribbonPipeline;
@property(nonatomic, strong) id<MTLRenderPipelineState> ribbonPrepass;
@property(nonatomic, strong) id<MTLDepthStencilState> ribbonDepth;
@property(nonatomic, strong) id<MTLDepthStencilState> ribbonSurfaceDepth;
@property(nonatomic) CFTimeInterval lastFrame;
@property(nonatomic) float elapsed;
@end

@implementation WelcomeCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return nil;
    self = [super initWithFrame:frame device:device];
    if (!self) return nil;
    self.paused = YES;
    self.preferredFramesPerSecond = 30;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    self.clearDepth = 1;
    self.framebufferOnly = YES;
    self.autoResizeDrawable = NO;
    self.elapsed = 12;
    NSError *error = nil;
    NSURL *url = [NSBundle.mainBundle URLForResource:@"Welcome" withExtension:@"metal"];
    NSString *source = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error] : nil;
    id<MTLLibrary> library = source ? [device newLibraryWithSource:source options:nil error:&error] : nil;
    if (!library) {
        fprintf(stderr, "ohmansy: welcome shader unavailable: %s\n", error.description.UTF8String);
        return nil;
    }
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"welcomeVertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"welcomeFragment"];
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    descriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
    self.pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    descriptor.vertexFunction = [library newFunctionWithName:@"ribbonVertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"ribbonFragment"];
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    self.ribbonPipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    descriptor.colorAttachments[0].writeMask = MTLColorWriteMaskNone;
    self.ribbonPrepass = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    MTLDepthStencilDescriptor *depth = [MTLDepthStencilDescriptor new];
    depth.depthCompareFunction = MTLCompareFunctionLessEqual;
    depth.depthWriteEnabled = NO;
    self.ribbonDepth = [device newDepthStencilStateWithDescriptor:depth];
    depth.depthWriteEnabled = YES;
    self.ribbonSurfaceDepth = [device newDepthStencilStateWithDescriptor:depth];
    self.commands = [device newCommandQueue];
    if (!self.pipeline || !self.ribbonPipeline || !self.ribbonPrepass || !self.commands) {
        fprintf(stderr, "ohmansy: welcome pipeline unavailable: %s\n", error.description.UTF8String);
        return nil;
    }
    self.delegate = self;
    fprintf(stderr, "ohmansy: Metal welcome ribbons ready\n");
    return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)acceptsFirstResponder { return NO; }
- (void)setAnimating:(BOOL)animating {
    if (self.paused == !animating) return;
    self.lastFrame = 0;
    self.paused = !animating;
    if (self.paused && !self.hidden) [self draw];
}
- (void)layout {
    [super layout];
    // Keep the ambient renderer inexpensive even on a large Retina display.
    CGFloat scale = MIN(self.window.backingScaleFactor ?: 1, 2);
    scale = MIN(scale, 2400 / MAX(1, self.bounds.size.width));
    CGSize size = CGSizeMake(MAX(1, self.bounds.size.width * scale), MAX(1, self.bounds.size.height * scale));
    if (!CGSizeEqualToSize(size, self.drawableSize)) self.drawableSize = size;
    if (self.paused && !self.hidden) [self draw];
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}
- (void)drawInMTKView:(MTKView *)view {
    if (self.hidden || !self.pipeline) return;
    MTLRenderPassDescriptor *pass = self.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = self.currentDrawable;
    if (!pass || !drawable) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (!self.paused && self.lastFrame) self.elapsed += MIN(now - self.lastFrame, 0.1);
    self.lastFrame = now;
    struct { vector_float2 size; float time; float padding; } uniforms = {
        {(float)self.drawableSize.width, (float)self.drawableSize.height}, self.elapsed, 0
    };
    id<MTLCommandBuffer> buffer = [self.commands commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:self.pipeline];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder setRenderPipelineState:self.ribbonPipeline];
    [encoder setDepthStencilState:self.ribbonDepth];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    // Disjoint depth envelopes guarantee this back-to-front transparency order.
    // Transparent fragments must not write depth and cut off layers behind them.
    uint32_t order[] = {0, 1, 2};
    for (int i = 0; i < 3; i++) {
        [encoder setVertexBytes:&order[i] length:sizeof(uint32_t) atIndex:1];
        // Resolve this ribbon's folds before blending its nearest surface.
        // The next ribbon is entirely closer, so it can safely replace depth.
        [encoder setRenderPipelineState:self.ribbonPrepass];
        [encoder setDepthStencilState:self.ribbonSurfaceDepth];
        [encoder setDepthBias:0.00001 slopeScale:1 clamp:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:256 * 12 * 6];
        [encoder setRenderPipelineState:self.ribbonPipeline];
        [encoder setDepthStencilState:self.ribbonDepth];
        [encoder setDepthBias:0 slopeScale:0 clamp:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:256 * 12 * 6];
    }
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}
@end
