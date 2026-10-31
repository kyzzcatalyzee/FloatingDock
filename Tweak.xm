// FloatDock by zilvyn
// Floating rounded dock for home button iPhones. The dock never hides: it stays on the Home Screen.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#define FD_DOMAIN @"com.zilvyn.floatdock"
#define FD_NOTIFY "com.zilvyn.floatdock/prefschanged"

@interface SBDockView : UIView @end

static BOOL  gEnabled = YES;
static CGFloat gSide = 12, gBottom = 10, gTop = 6, gRadius = 32;
static NSHashTable<UIView *> *gDocks;

static CGFloat FDFloat(NSUserDefaults *d, NSString *key, CGFloat def) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
}

static void FDLoadPrefs(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:FD_DOMAIN];
    id e = [d objectForKey:@"enabled"];
    gEnabled = e ? [e boolValue] : YES;
    gSide    = FDFloat(d, @"sideInset", 12);
    gBottom  = FDFloat(d, @"bottomMargin", 10);
    gTop     = FDFloat(d, @"topInset", 6);
    gRadius  = FDFloat(d, @"cornerRadius", 32);
}

// The dock background view (name differs a little between iOS versions).
static UIView *FDBackground(UIView *dock) {
    for (NSString *key in @[@"backgroundView", @"_backgroundView"]) {
        @try {
            id v = [dock valueForKey:key];
            if ([v isKindOfClass:[UIView class]]) return v;
        } @catch (__unused NSException *ex) {}
    }
    return nil;
}

static void FDApply(UIView *dock) {
    UIView *bg = FDBackground(dock);
    if (!bg) return;

    if (!gEnabled) {
        bg.layer.cornerRadius = 0;
        bg.layer.masksToBounds = NO;
        return;
    }
    CGRect b = dock.bounds;
    CGFloat w = MAX(0, b.size.width - gSide * 2.0);
    CGFloat h = MAX(0, b.size.height - gTop - gBottom);
    bg.frame = CGRectMake(gSide, gTop, w, h);
    bg.layer.cornerRadius = MIN(gRadius, MIN(w, h) / 2.0);
    if (@available(iOS 13.0, *)) bg.layer.cornerCurve = kCACornerCurveContinuous;
    bg.layer.masksToBounds = YES;
}

static void FDReloadAll(void) {
    FDLoadPrefs();
    for (UIView *d in gDocks.allObjects) {
        [d setNeedsLayout];
        [d layoutIfNeeded];
    }
}

static void FDPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ FDReloadAll(); });
}

%hook SBDockView
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
