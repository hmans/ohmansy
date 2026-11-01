// No application, window server, or VM is started by this regression test.
#define OHMANSY_CHROME_TESTING 1
#import "../../macos/RuntimeChrome.m"

@interface TestWindow : NSObject
@property(nonatomic, strong) NSView *contentView;
@property(nonatomic) NSWindowStyleMask styleMask;
@property(nonatomic) NSRect contentLayoutRect;
@property(nonatomic) BOOL titlebarAppearsTransparent;
@property(nonatomic) NSTitlebarSeparatorStyle titlebarSeparatorStyle;
@end
@implementation TestWindow
@end

@interface TestFrame : OhmansyFrame
@property(nonatomic, strong) TestWindow *testWindow;
@end
@implementation TestFrame
- (NSWindow *)window { return (NSWindow *)self.testWindow; }
@end

@interface TestGuest : NSView
@property(nonatomic, strong) TestWindow *testWindow;
@end
@implementation TestGuest
- (NSWindow *)window { return (NSWindow *)self.testWindow; }
@end

static int resizeRequests;
static int captureAttempts;
@interface TestKeyboardGuest : NSView
- (void)setFullGrab:(id)sender;
@end
@implementation TestKeyboardGuest
- (void)setFullGrab:(id)sender { captureAttempts++; }
@end
@interface TestKeyboardChrome : OhmansyChrome
@property(nonatomic) BOOL permissionGranted;
@end
@implementation TestKeyboardChrome
- (BOOL)keyboardPermissionGranted { return self.permissionGranted; }
- (CFMachPortRef)keyboardEventTap { return NULL; }
@end
static void EngineResize(id view, SEL selector) { resizeRequests++; }
@interface TestScrollEvent : NSObject
@property(nonatomic) CGFloat scrollingDeltaX;
@property(nonatomic) CGFloat scrollingDeltaY;
@property(nonatomic) NSEventPhase phase;
@end
@implementation TestScrollEvent
- (NSEventType)type { return NSEventTypeScrollWheel; }
- (NSEventModifierFlags)modifierFlags { return 0; }
- (BOOL)hasPreciseScrollingDeltas { return YES; }
@end
static NSInteger wheelX, wheelY;
static bool ReceiveWheel(id guest, SEL selector, NSEvent *event) {
    NSCAssert(!event.hasPreciseScrollingDeltas && event.phase == NSEventPhaseNone && event.momentumPhase == NSEventPhaseNone, @"Use the USB tablet's wheel path, not touch scrolling.");
    NSCAssert(event.type == NSEventTypeScrollWheel, @"Preserve the original event metadata.");
    wheelX += event.deltaX;
    wheelY += event.deltaY;
    return true;
}
static int invalidations, presentations;
static bool engineLock;
static bool TestEngineLock(void) { return engineLock; }
static void InvalidateLayer(id layer, SEL selector) { invalidations++; }
@interface TestRenderLayer : CALayer
@end
@implementation TestRenderLayer
- (void)displayIfNeeded { presentations++; }
@end

int main(void) {
    @autoreleasepool {
        TestKeyboardChrome *keyboardChrome = [TestKeyboardChrome new];
        keyboardChrome.guest = [TestKeyboardGuest new];
        [keyboardChrome updateKeyboardAccess];
        NSCAssert(captureAttempts == 0, @"Do not retry or prompt before permission is granted.");
        keyboardChrome.permissionGranted = YES;
        [keyboardChrome updateKeyboardAccess];
        NSCAssert(captureAttempts == 0, @"Permission must not automatically lock input.");
        keyboardChrome.stopped = YES;
        [keyboardChrome keyboard:nil];
        NSCAssert(!keyboardChrome.inputLocked && captureAttempts == 0, @"Launcher must never capture shortcuts.");
        keyboardChrome.stopped = NO;
        keyboardChrome.inputLocked = YES;
        [keyboardChrome updateKeyboardAccess];
        NSCAssert(captureAttempts == 1, @"Granting access must reconnect capture without a VM restart.");
        [keyboardChrome updateKeyboardAccess];
        NSCAssert(captureAttempts == 1, @"Repeated polls must not create duplicate event taps.");
        keyboardChrome.lastCaptureAttempt = 0;
        [keyboardChrome updateKeyboardAccess];
        NSCAssert(captureAttempts == 2, @"An explicit retry can bypass the retry delay.");
        NSCAssert(![keyboardChrome keyboardCaptureReady], @"Permission alone must not be reported as working capture.");
        [keyboardChrome releaseInput];
        keyboardChrome.lastCaptureAttempt = 0;
        [keyboardChrome updateKeyboardAccess];
        NSCAssert(!keyboardChrome.inputLocked && captureAttempts == 2, @"Polling must not relock released input.");
        keyboardChrome.inputLocked = YES;
        [keyboardChrome windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:nil]];
        NSCAssert(!keyboardChrome.inputLocked, @"Leaving the window must release input.");
        ActiveChrome = keyboardChrome;
        keyboardChrome.stopped = YES;
        NSEvent *command = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"q" charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:12];
        NSCAssert(!HandleGuestEvent(keyboardChrome.guest, @selector(description), command), @"Stopped guest must leave events to AppKit.");
        keyboardChrome.stopped = NO;
        NSCAssert(!HandleGuestEvent(keyboardChrome.guest, @selector(description), command), @"Unlocked guest must leave Command shortcuts to macOS.");
        keyboardChrome.inputLocked = YES;
        NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl | NSEventModifierFlagOption timestamp:0 windowNumber:0 context:nil characters:@"g" charactersIgnoringModifiers:@"g" isARepeat:NO keyCode:5];
        NSCAssert(HandleGuestEvent(keyboardChrome.guest, @selector(description), escape) && !keyboardChrome.inputLocked, @"Escape shortcut must release input without forwarding it.");
        OriginalHandleEvent = (IMP)ReceiveWheel;
        TestScrollEvent *scroll = [TestScrollEvent new];
        scroll.scrollingDeltaX = 25;
        scroll.scrollingDeltaY = -6;
        HandleGuestEvent(keyboardChrome.guest, @selector(description), (NSEvent *)scroll);
        NSCAssert(wheelX == 2 && wheelY == 0, @"Forward horizontal steps and retain sub-step movement.");
        scroll.scrollingDeltaX = 0;
        HandleGuestEvent(keyboardChrome.guest, @selector(description), (NSEvent *)scroll);
        NSCAssert(wheelX == 2 && wheelY == -1, @"Slow scrolling must accumulate with the correct direction.");
        scroll.phase = NSEventPhaseBegan;
        scroll.scrollingDeltaY = -9;
        HandleGuestEvent(keyboardChrome.guest, @selector(description), (NSEvent *)scroll);
        NSCAssert(wheelY == -1, @"New gestures must clear stale fractions.");
        ActiveChrome = nil;
        OriginalLayerNeedsDisplay = (IMP)InvalidateLayer;
        EngineLockHeld = TestEngineLock;
        TestRenderLayer *renderLayer = [TestRenderLayer new];
        PresentReadyGuestFrame(renderLayer, @selector(setNeedsDisplay));
        NSCAssert(invalidations == 1 && presentations == 1, @"Ready frames should draw immediately.");
        engineLock = true;
        PresentReadyGuestFrame(renderLayer, @selector(setNeedsDisplay));
        NSCAssert(invalidations == 2 && presentations == 1, @"Never draw while holding QEMU's rendering lock.");
        engineLock = false;
        ImmediatePresentationEnabled = NO;
        PresentReadyGuestFrame(renderLayer, @selector(setNeedsDisplay));
        NSCAssert(invalidations == 3 && presentations == 1, @"The A/B toggle must restore deferred drawing.");
        ImmediatePresentationEnabled = YES;
        OriginalResizeWindow = (IMP)EngineResize;
        TestGuest *guest = [[TestGuest alloc] initWithFrame:NSMakeRect(0, 0, 1080, 700)];
        guest.testWindow = [TestWindow new];
        guest.testWindow.contentView = [[OhmansyFrame alloc] initWithFrame:NSMakeRect(0, 0, 1100, 760)];
        for (int i = 0; i < 100; i++) {
            ResizeGuestWithoutShrinkingFrame(guest, NSSelectorFromString(@"resizeWindow"));
        }
        NSCAssert(resizeRequests == 0, @"Guest mode changes must not resize the host window after wrapping.");
        guest.testWindow.contentView = guest;
        ResizeGuestWithoutShrinkingFrame(guest, NSSelectorFromString(@"resizeWindow"));
        NSCAssert(resizeRequests == 1, @"Before wrapping, retain QEMU's original setup behavior.");
        guest.testWindow.contentView = nil;
        guest.testWindow = nil;
        OhmansyChrome *chrome = [OhmansyChrome new];
        TestFrame *frame = [[TestFrame alloc] initWithFrame:NSMakeRect(0, 0, 1200, 800)];
        frame.testWindow = [TestWindow new];
        frame.testWindow.contentLayoutRect = NSMakeRect(0, 0, 1200, 750);
        frame.well = [NSView new];
        frame.well.wantsLayer = YES;
        frame.guest = [NSView new];
        [frame addSubview:frame.well];
        [frame.well addSubview:frame.guest];
        frame.testWindow.styleMask = NSWindowStyleMaskFullScreen;
        [frame layout];
        NSCAssert(NSEqualRects(frame.well.frame, frame.bounds), @"Full screen must fill every edge, including the titlebar area.");
        NSCAssert(frame.well.layer.cornerRadius == 0, @"Full screen must not clip the desktop corners.");
        NSCAssert(NSEqualRects(frame.guest.frame, frame.well.bounds), @"Guest must fill the full-screen surface.");
        frame.testWindow.styleMask = NSWindowStyleMaskTitled;
        [frame layout];
        NSCAssert(NSEqualRects(frame.well.frame, NSMakeRect(10, 10, 1180, 730)), @"Leaving full screen must restore the original inset.");
        NSCAssert(frame.well.layer.cornerRadius == 12, @"Leaving full screen must restore rounded corners.");
        frame.testWindow = nil;
        for (NSValue *value in @[[NSValue valueWithSize:NSMakeSize(1200, 500)],
                                 [NSValue valueWithSize:NSMakeSize(600, 1000)]]) {
            NSSize requested = value.sizeValue;
            NSCAssert(NSEqualSizes([chrome windowWillResize:(NSWindow *)[TestWindow new] toSize:requested], requested),
                      @"Wide and tall host windows must retain the requested aspect ratio.");
        }
        fprintf(stdout, "Runtime chrome regression passed: repeated mode changes cannot shrink the framed window.\n");
    }
    return 0;
}
