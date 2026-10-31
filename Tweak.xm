// FloatDock by zilvyn
// Floating rounded dock for home button iPhones. The dock never hides: it stays on the Home Screen.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#define FD_DOMAIN @"com.zilvyn.floatdock"
#define FD_NOTIFY "com.zilvyn.floatdock/prefschanged"

@interface SBDockView : UIView @end

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

// Round the dock background and every material view inside it (LiquidAss draws its glass there).
static void FDStyleBackground(UIView *root, CGFloat radius, int depth) {
    if (depth > 6) return;
    for (UIView *v in root.subviews) {
        NSString *cn = NSStringFromClass(v.class);
        if ([cn isEqualToString:@"MTMaterialView"] ||
            [cn containsString:@"BackgroundView"] ||
            [cn containsString:@"WallpaperEffect"]) {
            FDRound(v, radius);
        }
        FDStyleBackground(v, radius, depth + 1);
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
        gAdjusting = NO;
    }
}

static void FDReloadAll(void) {
    FDLoadPrefs();
    for (UIView *d in gDocks.allObjects) {
        [d.superview setNeedsLayout];
        [d setNeedsLayout];
        [d layoutIfNeeded];
        FDApply(d);
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

%ctor {
    FDLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        FDPrefsChanged, CFSTR(FD_NOTIFY), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
