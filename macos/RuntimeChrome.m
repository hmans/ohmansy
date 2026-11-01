// Own-process Cocoa adapter for the pinned development QEMU runtime.
// Uses AppKit view composition; no QEMU source or guest pixels are copied here.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <GameplayKit/GameplayKit.h>
#import "WelcomeCanvas.h"
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdbool.h>

@interface OhmansyFrame : NSView
@property(nonatomic, strong) NSView *well;
@property(nonatomic, strong) NSView *guest;
@property(nonatomic, strong) CAGradientLayer *welcomeGradient;
@property(nonatomic, strong) NSArray<CAGradientLayer *> *welcomeGlows;
@property(nonatomic, strong) NSArray<GKNoise *> *welcomeNoise;
@property(nonatomic) NSTimeInterval noiseEpoch;
@property(nonatomic) NSTimeInterval lastNoiseRefresh;
@property(nonatomic) BOOL showingWelcome;
@property(nonatomic, strong) WelcomeCanvas *welcomeCanvas;
@property(nonatomic) BOOL triedWelcomeCanvas;
- (void)updateWelcomeAnimation;
@end
@implementation OhmansyFrame
- (void)updateWelcomeAnimation {
    if (!self.triedWelcomeCanvas) {
        self.triedWelcomeCanvas = YES;
        self.welcomeCanvas = [[WelcomeCanvas alloc] initWithFrame:self.well.bounds];
        if (self.welcomeCanvas) [self.well addSubview:self.welcomeCanvas positioned:NSWindowBelow relativeTo:nil];
    }
    if (self.welcomeCanvas) {
        self.welcomeCanvas.hidden = !self.showingWelcome;
        [self.welcomeCanvas setAnimating:self.showingWelcome && self.window.visible &&
            (self.window.occlusionState & NSWindowOcclusionStateVisible) &&
            !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion];
        return;
    }
    if (!self.welcomeGradient) {
        self.welcomeGradient = [CAGradientLayer layer];
        self.welcomeGradient.colors = @[
            (__bridge id)[NSColor colorWithWhite:0.15 alpha:1].CGColor,
            (__bridge id)[NSColor colorWithWhite:0.19 alpha:1].CGColor];
        self.welcomeGradient.startPoint = CGPointMake(0.5, 0);
        self.welcomeGradient.endPoint = CGPointMake(0.5, 1);
        [self.well.layer insertSublayer:self.welcomeGradient atIndex:0];
        NSMutableArray *glows = [NSMutableArray array];
        NSMutableArray *noises = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            CAGradientLayer *glow = [CAGradientLayer layer];
            // Broad directional washes avoid the bright centres of spotlights.
            glow.type = kCAGradientLayerAxial;
            NSArray<NSColor *> *palette = @[
                [NSColor colorWithSRGBRed:0.22 green:0.38 blue:0.62 alpha:1],
                [NSColor colorWithSRGBRed:0.43 green:0.25 blue:0.54 alpha:1],
                [NSColor colorWithSRGBRed:0.16 green:0.43 blue:0.43 alpha:1]];
            NSColor *color = palette[i];
            glow.colors = @[
                (__bridge id)[color colorWithAlphaComponent:0.42].CGColor,
                (__bridge id)[color colorWithAlphaComponent:0.32].CGColor,
                (__bridge id)[color colorWithAlphaComponent:0].CGColor];
            glow.locations = @[@0, @0.35, @1];
            glow.startPoint = CGPointMake(0.2 + i * 0.3, 0.35 + i * 0.15);
            glow.endPoint = CGPointMake(glow.startPoint.x + 0.55, glow.startPoint.y + 0.55);
            [self.well.layer insertSublayer:glow atIndex:i + 1];
            [glows addObject:glow];
            GKPerlinNoiseSource *source = [[GKPerlinNoiseSource alloc]
                initWithFrequency:1 octaveCount:2 persistence:0.35 lacunarity:2 seed:173 + i * 101];
            [noises addObject:[GKNoise noiseWithNoiseSource:source]];
        }
        self.welcomeGlows = glows;
        self.welcomeNoise = noises;
        self.noiseEpoch = NSProcessInfo.processInfo.systemUptime;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.welcomeGradient.hidden = !self.showingWelcome;
    for (CAGradientLayer *glow in self.welcomeGlows) glow.hidden = !self.showingWelcome;
    [CATransaction commit];
    BOOL animate = self.showingWelcome && self.window.visible &&
        (self.window.occlusionState & NSWindowOcclusionStateVisible) &&
        !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (!animate) {
        for (CAGradientLayer *glow in self.welcomeGlows) [glow removeAllAnimations];
        self.lastNoiseRefresh = 0;
    } else if (NSProcessInfo.processInfo.systemUptime - self.lastNoiseRefresh >= 19) {
        // Sample ahead, then let Core Animation interpolate on the compositor.
        // Refresh before the segment ends, using the same continuous noise clock.
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        for (NSUInteger i = 0; i < self.welcomeGlows.count; i++) {
            GKNoise *noise = self.welcomeNoise[i];
            NSMutableArray *centers = [NSMutableArray array];
            NSMutableArray *edges = [NSMutableArray array];
            NSMutableArray *opacities = [NSMutableArray array];
            for (int sample = 0; sample <= 200; sample++) {
                float t = (now - self.noiseEpoch + sample * 0.1) * (0.09 + i * 0.018);
                CGFloat x = 0.5 + 0.52 * [noise valueAtPosition:(vector_float2){t, 1.37}];
                CGFloat y = 0.5 + 0.46 * [noise valueAtPosition:(vector_float2){t, 17.83}];
                CGFloat radius = 0.65 + 0.18 * [noise valueAtPosition:(vector_float2){t, 31.19}];
                CGFloat opacity = 0.72 + 0.25 * [noise valueAtPosition:(vector_float2){t, 49.71}];
                CGFloat angle = i * 2.094 + 0.8 * [noise valueAtPosition:(vector_float2){t, 63.41}];
                CGFloat dx = cos(angle) * radius * 0.5;
                CGFloat dy = sin(angle) * radius * 0.5;
                [centers addObject:[NSValue valueWithPoint:NSMakePoint(x - dx, y - dy)]];
                [edges addObject:[NSValue valueWithPoint:NSMakePoint(x + dx, y + dy)]];
                [opacities addObject:@(opacity)];
            }
            NSArray *paths = @[@"startPoint", @"endPoint", @"opacity"];
            NSArray *values = @[centers, edges, opacities];
            for (NSUInteger channel = 0; channel < paths.count; channel++) {
                CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:paths[channel]];
                animation.values = values[channel];
                animation.duration = 20;
                [self.welcomeGlows[i] addAnimation:animation forKey:paths[channel]];
            }
        }
        self.lastNoiseRefresh = now;
    }
}
- (void)layout {
    [super layout];
    BOOL fullScreen = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    NSRect usable = [self convertRect:self.window.contentLayoutRect fromView:nil];
    NSRect wellFrame = fullScreen ? self.bounds : NSInsetRect(NSIntersectionRect(self.bounds, usable), 10, 10);
    self.well.layer.cornerRadius = fullScreen ? 0 : 12;
    if (!NSEqualRects(self.well.frame, wellFrame)) self.well.frame = wellFrame;
    if (!NSEqualRects(self.guest.frame, self.well.bounds)) self.guest.frame = self.well.bounds;
    if (!NSEqualRects(self.welcomeCanvas.frame, self.well.bounds)) self.welcomeCanvas.frame = self.well.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.welcomeGradient.frame = self.well.bounds;
    for (CAGradientLayer *glow in self.welcomeGlows) glow.frame = self.well.bounds;
    [CATransaction commit];
    self.window.titlebarAppearsTransparent = YES;
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(rect);
    if (!self.well.hidden && !(self.window.styleMask & NSWindowStyleMaskFullScreen)) {
        // Draw in the surrounding frame: a shadow on a child layer can be
        // clipped by AppKit's backing layers before it reaches the gutter.
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [NSShadow new];
        shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.65];
        shadow.shadowBlurRadius = 10;
        shadow.shadowOffset = NSMakeSize(0, -4);
        [shadow set];
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.well.frame xRadius:12 yRadius:12] fill];
        [NSGraphicsContext restoreGraphicsState];
    }
}
@end

static IMP OriginalResizeWindow;
static IMP OriginalLayerNeedsDisplay;
static bool (*EngineLockHeld)(void);
static BOOL ImmediatePresentationEnabled = YES;
static BOOL PresentingGuestFrame;
static void PresentReadyGuestFrame(CALayer *layer, SEL selector) {
    ((void (*)(id, SEL))OriginalLayerNeedsDisplay)(layer, selector);
    // QEMU queues dirty frames onto the main thread after releasing its lock.
    // Render there instead of deferring the work to the next CA transaction.
    // Other invalidations retain normal behavior, including background threads.
    if (ImmediatePresentationEnabled && NSThread.isMainThread &&
        EngineLockHeld && !EngineLockHeld() && !PresentingGuestFrame) {
        PresentingGuestFrame = YES;
        [layer displayIfNeeded];
        PresentingGuestFrame = NO;
    }
}
static void ResizeGuestWithoutShrinkingFrame(NSView *guest, SEL selector) {
    // The engine assumes its guest view is the window's content view. With our
    // inset, feeding guest dimensions back into the outer window shrinks it on
    // each mode switch. The host window owns sizing once the frame is installed.
    if ([guest.window.contentView isKindOfClass:OhmansyFrame.class]) return;
    ((void (*)(id, SEL))OriginalResizeWindow)(guest, selector);
}

@interface OhmansyChrome : NSObject <NSToolbarDelegate, NSWindowDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) NSView *guest;
@property(nonatomic, strong) id previousDelegate;
@property(nonatomic) BOOL installed;
@property(nonatomic, strong) NSStackView *launcher;
@property(nonatomic, strong) NSButton *startButton;
@property(nonatomic, strong) NSTimer *statusTimer;
@property(nonatomic) BOOL polling;
@property(nonatomic) BOOL stopped;
@property(nonatomic) BOOL quitAfterShutdown;
@property(nonatomic) BOOL toolbarWasVisible;
@property(nonatomic, strong) NSToolbarItem *keyboardItem;
@property(nonatomic, strong) NSButton *keyboardSetupButton;
@property(nonatomic, strong) NSPopover *keyboardPopover;
@property(nonatomic, strong) NSTextField *keyboardDetail;
@property(nonatomic) NSTimeInterval lastCaptureAttempt;
@property(nonatomic) BOOL inputLocked;
- (void)install;
- (void)releaseInput;
- (void)keyboard:(id)sender;
@end

static __weak OhmansyChrome *ActiveChrome;
static IMP OriginalHandleEvent, OriginalGrabMouse, OriginalUngrabMouse;
// The pinned runtime sends precise scroll events as touch gestures or relative
// axes. Our USB tablet accepts wheel buttons instead. Preserve event metadata
// while selecting the runtime's discrete wheel path.
@interface OhmansyWheelEvent : NSProxy
@property(nonatomic, strong) NSEvent *source;
@property(nonatomic) CGFloat deltaX;
@property(nonatomic) CGFloat deltaY;
@end
@implementation OhmansyWheelEvent
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.source methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.source]; }
- (BOOL)hasPreciseScrollingDeltas { return NO; }
- (NSEventPhase)phase { return NSEventPhaseNone; }
- (NSEventPhase)momentumPhase { return NSEventPhaseNone; }
@end

static CGFloat ScrollRemainderX, ScrollRemainderY;
static void ForwardWheelAxis(NSView *guest, SEL selector, NSEvent *source, CGFloat delta, BOOL horizontal) {
    if (!isfinite(delta)) return;
    OhmansyWheelEvent *wheel = [OhmansyWheelEvent alloc];
    wheel.source = source;
    wheel.deltaX = horizontal ? copysign(1, delta) : 0;
    wheel.deltaY = horizontal ? 0 : copysign(1, delta);
    for (NSInteger step = 0; step < MIN(fabs(delta), 100); step++) {
        ((bool (*)(id, SEL, id))OriginalHandleEvent)(guest, selector, wheel);
    }
}

static bool HandleGuestEvent(NSView *guest, SEL selector, NSEvent *event) {
    OhmansyChrome *chrome = ActiveChrome;
    if (chrome.stopped) return false;
    BOOL click = event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown ||
                 event.type == NSEventTypeOtherMouseDown;
    if (click && !chrome.inputLocked && event.window == chrome.window &&
        !guest.hiddenOrHasHiddenAncestor && !chrome.window.attachedSheet && !chrome.keyboardPopover.shown) {
        NSView *content = chrome.window.contentView;
        NSView *hit = [content hitTest:[content convertPoint:event.locationInWindow fromView:nil]];
        if (hit == guest || [hit isDescendantOf:guest]) {
            [chrome keyboard:nil];
            if (!chrome.inputLocked) return true; // A setup panel consumed this click.
        }
    }
    if (chrome.inputLocked && event.type == NSEventTypeKeyDown && event.keyCode == 5 &&
        (event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption)) ==
        (NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        [chrome releaseInput];
        return true;
    }
    if (!chrome.inputLocked && (event.modifierFlags & NSEventModifierFlagCommand)) return false;
    if (event.type == NSEventTypeScrollWheel && event.hasPreciseScrollingDeltas) {
        if (event.phase & NSEventPhaseBegan) ScrollRemainderX = ScrollRemainderY = 0;
        CGFloat x = event.scrollingDeltaX, y = event.scrollingDeltaY;
        if (!isfinite(x) || !isfinite(y)) return true;
        // Ten host points per wheel step; retain fractions for slow movement.
        ScrollRemainderX += x / 10;
        ScrollRemainderY += y / 10;
        CGFloat stepsX = trunc(ScrollRemainderX), stepsY = trunc(ScrollRemainderY);
        ScrollRemainderX -= stepsX;
        ScrollRemainderY -= stepsY;
        ForwardWheelAxis(guest, selector, event, stepsX, YES);
        ForwardWheelAxis(guest, selector, event, stepsY, NO);
        return true;
    }
    return ((bool (*)(id, SEL, id))OriginalHandleEvent)(guest, selector, event);
}
static void GrabGuestMouse(NSView *guest, SEL selector) {
    if (ActiveChrome.stopped) return;
    ((void (*)(id, SEL))OriginalGrabMouse)(guest, selector);
    guest.window.title = ActiveChrome.inputLocked ? @"try ohmansy — Input locked · ⌃⌥G to release" : @"try ohmansy";
}
static void UngrabGuestMouse(NSView *guest, SEL selector) {
    ((void (*)(id, SEL))OriginalUngrabMouse)(guest, selector);
    ActiveChrome.inputLocked = NO;
    [ActiveChrome releaseInput];
}

static NSDictionary *ReadReply(FILE *stream, NSInteger identifier) {
    char line[65536];
    while (fgets(line, sizeof(line), stream)) {
        NSData *data = [[NSString stringWithUTF8String:line] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (reply[@"QMP"] || [reply[@"id"] isEqual:@(identifier)]) return reply;
    }
    return nil;
}

@implementation OhmansyChrome
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.previousDelegate respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return [self.previousDelegate respondsToSelector:selector] ? self.previousDelegate : [super forwardingTargetForSelector:selector];
}
- (NSView *)findGuest:(NSView *)view {
    if ([NSStringFromClass(view.class) isEqualToString:@"QemuCocoaView"]) return view;
    for (NSView *child in view.subviews) {
        NSView *found = [self findGuest:child];
        if (found) return found;
    }
    return nil;
}
- (void)renameMenu:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        item.title = [item.title stringByReplacingOccurrencesOfString:@"Try Omarchy" withString:@"try ohmansy"];
        if (item.submenu) [self renameMenu:item.submenu];
        if ([item.title isEqualToString:@"Quit try ohmansy"]) {
            item.target = self;
            item.action = @selector(quit:);
        }
    }
}
- (void)install {
    if (self.installed) return;
    // This helper is spawned directly rather than by Launch Services. Ask the
    // system to resolve its compiled bundle icon, including Icon Composer's
    // mask and appearance, instead of assigning the raw ICNS bitmap.
    NSImage *systemIcon = [NSWorkspace.sharedWorkspace iconForFile:NSBundle.mainBundle.bundlePath];
    // NSWorkspace returns a lazy Icon Services representation. Materialize it
    // before handing it to the Dock; passing the reference through this
    // directly launched helper can display the generic application placeholder.
    NSBitmapImageRep *dockBitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:1024 pixelsHigh:1024
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    dockBitmap.size = NSMakeSize(512, 512);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:dockBitmap];
    [systemIcon drawInRect:NSMakeRect(0, 0, 512, 512)];
    [NSGraphicsContext restoreGraphicsState];
    NSImage *dockIcon = [[NSImage alloc] initWithSize:dockBitmap.size];
    [dockIcon addRepresentation:dockBitmap];
    NSApp.applicationIconImage = dockIcon;
    // Load the fallback image only for the launcher illustration.
    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"Ohmansy" withExtension:@"icns"];
    NSImage *icon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
    for (NSWindow *window in NSApp.windows) {
        NSView *guest = [self findGuest:window.contentView];
        if (!guest) continue;
        self.installed = YES;
        self.window = window;
        self.guest = guest;
        ActiveChrome = self;
        OriginalHandleEvent = method_setImplementation(class_getInstanceMethod(guest.class, NSSelectorFromString(@"handleEvent:")), (IMP)HandleGuestEvent);
        OriginalGrabMouse = method_setImplementation(class_getInstanceMethod(guest.class, NSSelectorFromString(@"grabMouse")), (IMP)GrabGuestMouse);
        OriginalUngrabMouse = method_setImplementation(class_getInstanceMethod(guest.class, NSSelectorFromString(@"ungrabMouse")), (IMP)UngrabGuestMouse);
        self.previousDelegate = window.delegate;
        Class renderLayer = NSClassFromString(@"QemuCGLLayer");
        EngineLockHeld = (bool (*)(void))dlsym(RTLD_DEFAULT, "bql_locked");
        Method invalidate = class_getInstanceMethod(renderLayer, @selector(setNeedsDisplay));
        if (invalidate && EngineLockHeld && !OriginalLayerNeedsDisplay) {
            OriginalLayerNeedsDisplay = method_getImplementation(invalidate);
            // Add an override only to QEMU's layer, never to CALayer itself.
            if (!class_addMethod(renderLayer, @selector(setNeedsDisplay),
                                 (IMP)PresentReadyGuestFrame, method_getTypeEncoding(invalidate))) {
                OriginalLayerNeedsDisplay = NULL;
            }
        }
        Method resize = class_getInstanceMethod(guest.class, NSSelectorFromString(@"resizeWindow"));
        if (resize && !OriginalResizeWindow) {
            OriginalResizeWindow = method_setImplementation(resize, (IMP)ResizeGuestWithoutShrinkingFrame);
        }
        NSRect oldFrame = window.frame;
        OhmansyFrame *frame = [[OhmansyFrame alloc] initWithFrame:window.contentView.bounds];
        frame.well = [[NSView alloc] initWithFrame:NSInsetRect(frame.bounds, 10, 10)];
        frame.well.wantsLayer = YES;
        frame.well.layer.backgroundColor = NSColor.blackColor.CGColor;
        frame.well.layer.cornerRadius = 12;
        frame.well.layer.masksToBounds = YES;
        frame.guest = guest;
        [guest removeFromSuperview];
        [frame addSubview:frame.well];
        [frame.well addSubview:guest];
        window.contentView = frame;
        window.delegate = self;
        window.title = @"try ohmansy";
        window.titlebarAppearsTransparent = YES;
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        window.backgroundColor = NSColor.windowBackgroundColor;
        window.styleMask |= NSWindowStyleMaskFullSizeContentView | NSWindowStyleMaskResizable;
        window.contentResizeIncrements = NSMakeSize(1, 1);
        window.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"ohmansy.vm"];
        toolbar.delegate = self;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        window.toolbar = toolbar;
        [window setFrame:oldFrame display:YES];
        window.contentMinSize = NSMakeSize(480, 360);
        [window setContentSize:NSMakeSize(1100, 760)];
        [window center];
        [frame setNeedsLayout:YES];
        [window makeFirstResponder:guest];
        [self renameMenu:NSApp.mainMenu];
        NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
        NSMenuItem *keyboardMenu = [appMenu addItemWithTitle:@"Keyboard Shortcuts…" action:@selector(showKeyboardSetup:) keyEquivalent:@""];
        keyboardMenu.target = self;
        NSImageView *portrait = [NSImageView imageViewWithImage:icon];
        portrait.imageScaling = NSImageScaleProportionallyUpOrDown;
        portrait.wantsLayer = YES;
        portrait.layer.cornerRadius = 32;
        portrait.layer.masksToBounds = YES;
        [portrait.widthAnchor constraintEqualToConstant:156].active = YES;
        [portrait.heightAnchor constraintEqualToConstant:156].active = YES;
        NSTextField *heading = [NSTextField labelWithString:@"try ohmansy"];
        heading.font = [NSFont systemFontOfSize:40 weight:NSFontWeightHeavy];
        self.startButton = [NSButton buttonWithTitle:@"Start ohmansy" target:self action:@selector(start:)];
        self.startButton.bezelStyle = NSBezelStyleRounded;
        self.startButton.controlSize = NSControlSizeLarge;
        self.startButton.bezelColor = [NSColor colorWithSRGBRed:0.08 green:0.39 blue:0.96 alpha:1];
        self.startButton.keyEquivalent = @"\r";
        self.launcher = [NSStackView stackViewWithViews:@[portrait, heading, self.startButton]];
        self.launcher.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.launcher.spacing = 20;
        self.launcher.translatesAutoresizingMaskIntoConstraints = NO;
        self.keyboardSetupButton = [NSButton buttonWithTitle:@"Set Up Keyboard Shortcuts…" target:self action:@selector(showKeyboardSetup:)];
        [self.launcher addArrangedSubview:self.keyboardSetupButton];
        [frame.well addSubview:self.launcher];
        [NSLayoutConstraint activateConstraints:@[
            [self.launcher.centerXAnchor constraintEqualToAnchor:frame.well.centerXAnchor],
            [self.launcher.centerYAnchor constraintEqualToAnchor:frame.well.centerYAnchor]]];
        [self showStopped:YES];
        [self updateKeyboardAccess];
        self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(pollStatus:) userInfo:nil repeats:YES];
        fprintf(stderr, "ohmansy: native GPU window adapter installed\n");
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"dev.hmans.ohmansy.runtimeReady" object:nil userInfo:nil deliverImmediately:YES];
        break;
    }
}
- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)size {
    // QEMU's delegate enforces the framebuffer ratio. The host owns geometry.
    return size;
}
- (NSApplicationPresentationOptions)window:(NSWindow *)window
        willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)options {
    return (options & ~(NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar)) |
        NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar |
        NSApplicationPresentationAutoHideToolbar;
}
- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    self.toolbarWasVisible = self.window.toolbar.visible;
    self.window.toolbar.visible = NO;
    if ([self.previousDelegate respondsToSelector:_cmd])
        [self.previousDelegate windowWillEnterFullScreen:notification];
}
- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    [self.window.contentView setNeedsLayout:YES];
    [self.window.contentView layoutSubtreeIfNeeded];
    if ([self.previousDelegate respondsToSelector:_cmd])
        [self.previousDelegate windowDidEnterFullScreen:notification];
}
- (void)windowDidExitFullScreen:(NSNotification *)notification {
    self.window.toolbar.visible = self.toolbarWasVisible;
    [self.window.contentView setNeedsLayout:YES];
    [self.window.contentView layoutSubtreeIfNeeded];
    if ([self.previousDelegate respondsToSelector:_cmd])
        [self.previousDelegate windowDidExitFullScreen:notification];
}
- (void)windowDidFailToEnterFullScreen:(NSWindow *)window {
    self.window.toolbar.visible = self.toolbarWasVisible;
    [self.window.contentView setNeedsLayout:YES];
    if ([self.previousDelegate respondsToSelector:_cmd])
        [self.previousDelegate windowDidFailToEnterFullScreen:window];
}
- (void)showStopped:(BOOL)stopped {
    self.stopped = stopped;
    if (stopped) [self releaseInput];
    OhmansyFrame *frame = (OhmansyFrame *)self.window.contentView;
    self.guest.hidden = stopped;
    frame.showingWelcome = stopped;
    [frame updateWelcomeAnimation];
    frame.needsLayout = YES;
    NSColor *welcomeColor = [NSColor.controlBackgroundColor blendedColorWithFraction:0.045 ofColor:NSColor.whiteColor];
    frame.well.layer.backgroundColor = (stopped ? welcomeColor : NSColor.blackColor).CGColor;
    frame.needsDisplay = YES;
    self.launcher.hidden = !stopped;
    self.startButton.enabled = YES;
    [self.window makeFirstResponder:stopped ? self.startButton : self.guest];
}
- (void)pollStatus:(NSTimer *)timer {
    [self updateKeyboardAccess];
    [(OhmansyFrame *)self.window.contentView updateWelcomeAnimation];
    if (self.polling) return;
    self.polling = YES;
    [self command:@"query-status" completion:^(NSDictionary *result) {
        self.polling = NO;
        NSString *status = result[@"status"];
        if (!status) return;
        BOOL stopped = [status isEqualToString:@"prelaunch"] || [status isEqualToString:@"shutdown"];
        if (stopped != self.stopped) [self showStopped:stopped];
        if (stopped && self.quitAfterShutdown) [self sendCommand:@"quit"];
    }];
}
- (void)start:(id)sender {
    self.startButton.enabled = NO;
    [self command:@"system_reset" completion:^(NSDictionary *result) {
        if (!result) { self.startButton.enabled = YES; return; }
        [self command:@"cont" completion:^(NSDictionary *result) {
            if (result) [self showStopped:NO];
            else self.startButton.enabled = YES;
        }];
    }];
}
- (void)quit:(id)sender {
    if (self.stopped) { [self sendCommand:@"quit"]; return; }
    self.quitAfterShutdown = YES;
    [self shutdown:sender];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"keyboard", @"settings", @"power"];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)inserted {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.target = self;
    if ([identifier isEqualToString:@"keyboard"]) {
        self.keyboardItem = item;
        item.label = @"Focus Keyboard";
        item.image = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:item.label];
        item.action = @selector(keyboard:);
    } else if ([identifier isEqualToString:@"settings"]) {
        NSMenuToolbarItem *controls = [[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier];
        controls.label = @"VM Controls";
        controls.image = [NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:controls.label];
        controls.toolTip = controls.label;
        NSMenu *menu = [[NSMenu alloc] initWithTitle:controls.label];
        NSMenuItem *files = [menu addItemWithTitle:@"Show VM Files" action:@selector(showFiles:) keyEquivalent:@""];
        files.target = self;
        NSMenuItem *keyboard = [menu addItemWithTitle:@"Keyboard Shortcuts…" action:@selector(showKeyboardSetup:) keyEquivalent:@""];
        keyboard.target = self;
        if (OriginalLayerNeedsDisplay) {
            NSMenuItem *latency = [menu addItemWithTitle:@"Low Latency" action:@selector(toggleLowLatency:) keyEquivalent:@""];
            latency.target = self;
            latency.state = ImmediatePresentationEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        }
        [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *stop = [menu addItemWithTitle:@"Force Stop…" action:@selector(forceStop:) keyEquivalent:@""];
        stop.target = self;
        controls.menu = menu;
        return controls;
    } else {
        item.label = @"Shut Down";
        item.image = [NSImage imageWithSystemSymbolName:@"power" accessibilityDescription:item.label];
        item.action = @selector(shutdown:);
    }
    item.toolTip = item.label;
    return item;
}
- (void)focus:(id)sender {
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.guest];
}
- (void)releaseInput {
    BOOL wasLocked = self.inputLocked;
    self.inputLocked = NO;
    CFMachPortRef tap = [self keyboardEventTap];
    if (tap && CFMachPortIsValid(tap)) CGEventTapEnable(tap, false);
    if (wasLocked && OriginalUngrabMouse)
        ((void (*)(id, SEL))OriginalUngrabMouse)(self.guest, NSSelectorFromString(@"ungrabMouse"));
    self.window.title = @"try ohmansy";
    [self updateKeyboardAccess];
}
- (void)windowDidResignKey:(NSNotification *)notification {
    [self releaseInput];
    if ([self.previousDelegate respondsToSelector:_cmd])
        [self.previousDelegate windowDidResignKey:notification];
}
- (CFMachPortRef)keyboardEventTap {
    // This adapter is paired with a checksum-pinned engine. Read the CF pointer
    // as bytes: object_getIvar would incorrectly treat it as an ARC object.
    Ivar ivar = class_getInstanceVariable(self.guest.class, "eventsTap");
    CFMachPortRef tap = NULL;
    if (ivar) memcpy(&tap, (char *)(__bridge void *)self.guest + ivar_getOffset(ivar), sizeof(tap));
    return tap;
}
- (BOOL)keyboardCaptureReady {
    CFMachPortRef tap = [self keyboardEventTap];
    return [self keyboardPermissionGranted] && tap && CFMachPortIsValid(tap) && CGEventTapIsEnabled(tap);
}
- (BOOL)keyboardPermissionGranted { return AXIsProcessTrusted(); }
- (void)updateKeyboardAccess {
    BOOL trusted = [self keyboardPermissionGranted];
    CFMachPortRef tap = [self keyboardEventTap];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (self.inputLocked && !self.stopped && trusted && !tap && now - self.lastCaptureAttempt >= 5) {
        self.lastCaptureAttempt = now;
        SEL retry = NSSelectorFromString(@"setFullGrab:");
        if ([self.guest respondsToSelector:retry]) {
            IMP implementation = [self.guest methodForSelector:retry];
            ((void (*)(id, SEL, id))implementation)(self.guest, retry, nil);
        }
    }
    tap = [self keyboardEventTap];
    if (tap && CFMachPortIsValid(tap)) CGEventTapEnable(tap, self.inputLocked && !self.stopped && trusted);
    BOOL ready = [self keyboardCaptureReady];
    NSString *title = self.inputLocked && ready ? @"Unlock input" : @"Lock input";
    self.keyboardItem.label = title;
    self.keyboardItem.enabled = !self.stopped;
    self.keyboardItem.toolTip = self.inputLocked ? @"Unlock input (Control–Option–G)" : @"Lock input to send Mac shortcuts to Linux";
    self.keyboardItem.image = [NSImage imageWithSystemSymbolName:self.inputLocked ? @"lock.fill" : @"lock.open"
                                      accessibilityDescription:title];
    self.keyboardSetupButton.hidden = trusted;
    self.keyboardDetail.stringValue = trusted && !self.inputLocked
        ? @"Click inside the running guest to lock input and send shortcuts to Linux. You can also use the lock button. Control–Option–G unlocks input. Switching apps also releases input."
        : ready ? @"Input is locked to Linux. Press Control–Option–G to return shortcuts to your Mac. Switching apps also releases input."
        : trusted
            ? @"Permission is granted, but keyboard capture is not connected. Click Retry. If it still fails, save your guest work and restart try ohmansy."
            : @"Allow try ohmansy under Device Control and Data Access (Accessibility on older macOS versions) so shortcuts reach Linux. If its toggle is already on, an older build may be authorized: remove that entry, then add the app revealed by Show App. We’ll retry capture when access is granted.";
}
- (void)keyboard:(id)sender {
    if (self.stopped) return;
    if (self.inputLocked) { [self releaseInput]; return; }
    if (![self keyboardPermissionGranted]) { [self showKeyboardSetup:sender]; return; }
    self.inputLocked = YES;
    self.lastCaptureAttempt = 0;
    [self updateKeyboardAccess];
    if ([self keyboardCaptureReady]) {
        [self focus:sender];
        SEL grab = NSSelectorFromString(@"grabMouse");
        ((void (*)(id, SEL))[self.guest methodForSelector:grab])(self.guest, grab);
    } else {
        [self releaseInput];
        [self showKeyboardSetup:sender];
    }
}
- (void)showKeyboardSetup:(id)sender {
    [self releaseInput];
    if (!self.keyboardPopover) {
        self.keyboardPopover = [NSPopover new];
        self.keyboardPopover.behavior = NSPopoverBehaviorTransient;
        NSViewController *controller = [NSViewController new];
        controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 260)];
        NSTextField *heading = [NSTextField labelWithString:@"Keyboard shortcuts"];
        heading.font = [NSFont boldSystemFontOfSize:17];
        self.keyboardDetail = [NSTextField wrappingLabelWithString:@""];
        self.keyboardDetail.font = [NSFont systemFontOfSize:13];
        NSButton *settings = [NSButton buttonWithTitle:@"Open Settings" target:self action:@selector(openKeyboardSettings:)];
        NSButton *retry = [NSButton buttonWithTitle:@"Retry" target:self action:@selector(retryKeyboard:)];
        NSButton *reveal = [NSButton buttonWithTitle:@"Show App" target:self action:@selector(showPermissionApp:)];
        NSStackView *buttons = [NSStackView stackViewWithViews:@[settings, reveal, retry]];
        NSStackView *stack = [NSStackView stackViewWithViews:@[heading, self.keyboardDetail, buttons]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 14;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [controller.view addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-20],
            [stack.topAnchor constraintEqualToAnchor:controller.view.topAnchor constant:20],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:controller.view.bottomAnchor constant:-20],
            [self.keyboardDetail.widthAnchor constraintEqualToConstant:340]]];
        self.keyboardPopover.contentViewController = controller;
    }
    [self updateKeyboardAccess];
    NSView *anchor = self.window.contentView;
    [self.keyboardPopover showRelativeToRect:NSMakeRect(NSMidX(anchor.bounds), NSMaxY(anchor.bounds) - 20, 1, 1)
                                     ofView:anchor preferredEdge:NSRectEdgeMinY];
}
- (void)openKeyboardSettings:(id)sender {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [NSWorkspace.sharedWorkspace openURL:url];
}
- (void)retryKeyboard:(id)sender {
    self.lastCaptureAttempt = 0;
    [self updateKeyboardAccess];
    if ([self keyboardCaptureReady]) {
        [self.keyboardPopover close];
        [self focus:sender];
    }
}
- (void)showPermissionApp:(id)sender {
    NSURL *app = NSBundle.mainBundle.bundleURL;
    for (NSURL *parent = app.URLByDeletingLastPathComponent; parent.path.length > 1;
         parent = parent.URLByDeletingLastPathComponent) {
        if ([parent.pathExtension isEqualToString:@"app"]) app = parent;
    }
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[app]];
}
- (void)toggleLowLatency:(NSMenuItem *)sender {
    ImmediatePresentationEnabled = !ImmediatePresentationEnabled;
    sender.state = ImmediatePresentationEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    fprintf(stderr, "ohmansy: immediate guest drawing %s\n", ImmediatePresentationEnabled ? "on" : "off");
}
- (void)showFiles:(id)sender {
    NSString *path = NSProcessInfo.processInfo.environment[@"OHMANSY_QMP_SOCKET"];
    if (path) [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path.stringByDeletingLastPathComponent isDirectory:YES]];
}
- (void)forceStop:(id)sender {
    [self releaseInput];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Force stop NixOS?";
    alert.informativeText = @"Unsaved changes can be lost.";
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Force Stop"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertSecondButtonReturn) [self sendCommand:@"quit"];
    }];
}
- (BOOL)windowShouldClose:(NSWindow *)window {
    [self quit:nil];
    return NO;
}
- (void)shutdown:(id)sender {
    if (self.stopped) return;
    [self releaseInput];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Shut down NixOS?";
    alert.informativeText = @"Save your work in the guest before shutting down.";
    [alert addButtonWithTitle:@"Shut Down"];
    [alert addButtonWithTitle:@"Keep Running"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [self sendCommand:@"system_powerdown"];
        else self.quitAfterShutdown = NO;
    }];
}
- (void)sendCommand:(NSString *)command {
    [self command:command completion:nil];
}
- (void)command:(NSString *)command completion:(void (^)(NSDictionary *))completion {
    NSString *path = NSProcessInfo.processInfo.environment[@"OHMANSY_QMP_SOCKET"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL success = NO;
        NSDictionary *result = nil;
        struct sockaddr_un address = {.sun_family = AF_UNIX};
        int descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
        if (descriptor >= 0 && path && strlen(path.fileSystemRepresentation) < sizeof(address.sun_path)) {
            struct timeval timeout = {.tv_sec = 5};
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            int noSignal = 1;
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
            strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
            if (connect(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0) {
                FILE *stream = fdopen(descriptor, "r+");
                if (stream) {
                    if (ReadReply(stream, -1)[@"QMP"]) {
                        fputs("{\"execute\":\"qmp_capabilities\",\"id\":1}\n", stream); fflush(stream);
                        if (ReadReply(stream, 1)[@"return"]) {
                            NSData *request = [NSJSONSerialization dataWithJSONObject:@{@"execute":command, @"id":@2} options:0 error:nil];
                            fwrite(request.bytes, 1, request.length, stream);
                            fputs("\n", stream); fflush(stream);
                            result = ReadReply(stream, 2)[@"return"];
                            success = result != nil;
                        }
                    }
                    fclose(stream);
                    descriptor = -1;
                }
            }
        }
        if (descriptor >= 0) close(descriptor);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result);
            if (success || [command isEqualToString:@"query-status"] || [command isEqualToString:@"quit"]) return;
            NSAlert *failure = [NSAlert new];
            failure.messageText = @"Could not control the VM";
            failure.informativeText = @"Try again, or use the NixOS power menu.";
            if (self.window.attachedSheet == nil) [failure beginSheetModalForWindow:self.window completionHandler:nil];
        });
    });
}
@end

#ifndef OHMANSY_CHROME_TESTING
__attribute__((constructor)) static void InstallOhmansyChrome(void) {
    @autoreleasepool {
        // Set before AppKit registers this directly launched process with macOS.
        NSProcessInfo.processInfo.processName = @"try ohmansy";
        static OhmansyChrome *chrome;
        chrome = [OhmansyChrome new];
        for (NSString *name in @[NSApplicationDidFinishLaunchingNotification, NSWindowDidBecomeMainNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    dispatch_async(dispatch_get_main_queue(), ^{ [chrome install]; });
                }];
        }
    }
}
#endif
