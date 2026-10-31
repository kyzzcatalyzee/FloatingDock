// FloatDock by zilvyn
// Floating rounded dock for home button iPhones. The dock never hides: it stays on the Home Screen.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#define FD_DOMAIN @"com.zilvyn.floatdock"
#define FD_NOTIFY "com.zilvyn.floatdock/prefschanged"

@interface SBDockView : UIView @end
@interface MTMaterialView : UIView @end

static BOOL    gEnabled = YES;
static CGFloat gSide = 34, gBottom = 20, gHeight = 82, gRadius = 30;
static BOOL    gAdjusting = NO;
static NSHashTable<UIView *> *gDocks;

static CGFloat FDFloat(NSUserDefaults *d, NSString *key, CGFloat def) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
}

static void FDLoadPrefs(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:FD_DOMAIN];
    id e = [d objectForKey:@"enabled"];
    gEnabled = e ? [e boolValue] : YES;
    gSide    = FDFloat(d, @"sideInset", 34);
    gBottom  = FDFloat(d, @"bottomMargin", 20);
    gHeight  = FDFloat(d, @"dockHeight", 82);
    gRadius  = FDFloat(d, @"cornerRadius", 30);
}

// Where the dock should sit inside its parent.
static CGRect FDTargetFrame(UIView *dock) {
    CGRect p = dock.superview.bounds;
    if (CGRectIsEmpty(p)) return dock.frame;
    CGFloat w = MAX(120.0, p.size.width - gSide * 2.0);
    return CGRectMake(CGRectGetMinX(p) + gSide, CGRectGetMaxY(p) - gBottom - gHeight, w, gHeight);
}

static void FDRound(UIView *v, CGFloat radius) {
    v.layer.cornerRadius = radius;
    v.layer.masksToBounds = (radius > 0);
    if (@available(iOS 13.0, *)) v.layer.cornerCurve = kCACornerCurveContinuous;
}

// LiquidAss draws a square outline (thin CAShapeLayer) for home button docks.
// Give that outline the same rounded shape as the dock.
static void FDFixBorders(UIView *root, CGFloat radius, int depth) {
    if (depth > 4) return;
    for (UIView *v in root.subviews) {
        for (CALayer *l in [v.layer.sublayers copy]) {
            if (![l isKindOfClass:[CAShapeLayer class]]) continue;
            CAShapeLayer *sl = (CAShapeLayer *)l;
            if (!sl.strokeColor || sl.lineWidth > 1.5) continue;
            if (sl.fillColor && CGColorGetAlpha(sl.fillColor) > 0.01) continue;
            CGRect r = CGRectInset(v.bounds, sl.lineWidth * 0.5, sl.lineWidth * 0.5);
            CGFloat cr = MAX(0.0, MIN(radius, MIN(r.size.width, r.size.height) / 2.0));
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            sl.frame = v.bounds;
            sl.path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:cr].CGPath;
            [CATransaction commit];
        }
        FDFixBorders(v, radius, depth + 1);
    }
}

// Round the dock background and every material view inside it (LiquidAss draws its glass there).
static void FDStyleBackground(UIView *root, CGFloat radius, int depth) {
    if (depth > 6) return;
    for (UIView *v in root.subviews) {
        NSString *cn = NSStringFromClass(v.class);
        if ([cn isEqualToString:@"MTMaterialView"] ||
            [cn containsString:@"BackgroundView"] ||
            [cn containsString:@"WallpaperEffect"]) {
            FDRound(v, radius);
            if (radius > 0) FDFixBorders(v, radius, 0);
        }
        FDStyleBackground(v, radius, depth + 1);
    }
}

// Make the dock icons spread out again for the new dock width.
static void FDRelayoutIcons(UIView *root, int depth) {
    if (depth > 6) return;
    for (UIView *v in root.subviews) {
        if ([NSStringFromClass(v.class) containsString:@"IconListView"]) {
            [v setNeedsLayout];
            SEL sel = NSSelectorFromString(@"layoutIconsNow");
            if ([v respondsToSelector:sel]) {
                void (*send)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
                send(v, sel);
            }
            [v layoutIfNeeded];
        } else {
            FDRelayoutIcons(v, depth + 1);
        }
    }
}

static void FDApply(UIView *dock) {
    if (gAdjusting || !dock.superview) return;
    CGFloat radius = gEnabled ? MIN(gRadius, gHeight / 2.0) : 0;
    @try {
        for (NSString *key in @[@"backgroundView", @"_backgroundView"]) {
            id v = [dock valueForKey:key];
            if ([v isKindOfClass:[UIView class]]) { FDRound((UIView *)v, radius); break; }
        }
    } @catch (__unused NSException *ex) {}
    FDStyleBackground(dock, radius, 0);
    if (!gEnabled) return;

    CGRect target = FDTargetFrame(dock);
    if (!CGRectEqualToRect(dock.frame, target)) {
        gAdjusting = YES;
        dock.frame = target;
        [dock setNeedsLayout];
        [dock layoutIfNeeded];
        FDRelayoutIcons(dock, 0);
        gAdjusting = NO;
    }
}

static BOOL FDInsideDock(UIView *v) {
    for (UIView *a = v.superview; a; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:@"SBDockView"]) return YES;
    }
    return NO;
}

static void FDReloadAll(void) {
    FDLoadPrefs();
    for (UIView *d in gDocks.allObjects) {
        [d.superview setNeedsLayout];
        [d setNeedsLayout];
        [d layoutIfNeeded];
        FDApply(d);
        FDRelayoutIcons(d, 0);
    }
}

static void FDPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ FDReloadAll(); });
}

%hook SBDockView
- (void)setFrame:(CGRect)frame {
    if (gEnabled && !gAdjusting && ((UIView *)self).superview) {
        %orig(FDTargetFrame((UIView *)self));
    } else {
        %orig(frame);
    }
}
- (void)layoutSubviews {
    %orig;
    if (!gDocks) gDocks = [NSHashTable weakObjectsHashTable];
    [gDocks addObject:(UIView *)self];
    FDApply((UIView *)self);
}
%end

// SpringBoard recreates the dock material after unlocking. Round it as soon as it appears,
// not only when the dock gets laid out again.
%hook MTMaterialView
- (void)didMoveToWindow {
    %orig;
    UIView *v = (UIView *)self;
    if (gEnabled && v.window && FDInsideDock(v)) {
        CGFloat r = MIN(gRadius, gHeight / 2.0);
        FDRound(v, r);
        FDFixBorders(v, r, 0);
        __weak UIView *wv = v;
        for (NSNumber *delay in @[@0.05, @0.3, @1.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIView *sv = wv;
                if (sv && gEnabled && sv.window) FDFixBorders(sv, MIN(gRadius, gHeight / 2.0), 0);
            });
        }
    }
}
- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    if (gEnabled && v.bounds.size.width > 160.0 && FDInsideDock(v)) {
        CGFloat r = MIN(gRadius, gHeight / 2.0);
        FDRound(v, r);
        FDFixBorders(v, r, 0);
    }
}
%end

%ctor {
    FDLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        FDPrefsChanged, CFSTR(FD_NOTIFY), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
