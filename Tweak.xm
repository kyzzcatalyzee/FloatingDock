// FloatDock by zilvyn
// Floating rounded dock for home button iPhones. The dock never hides: it stays on the Home Screen.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#define FD_DOMAIN @"com.zilvyn.floatdock"
#define FD_NOTIFY "com.zilvyn.floatdock/prefschanged"

@interface SBDockView : UIView @end
@interface MTMaterialView : UIView @end
@interface SBIconListView : UIView @end

static BOOL    gEnabled = YES;
static CGFloat gGap = 16, gPad = 12, gBottom = 20, gHeight = 82, gRadius = 30;
static NSInteger gCount = 4;   // number of dock icons (measured at runtime)
static CGFloat gIconW = 60;    // icon width (measured at runtime)
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
    gGap     = FDFloat(d, @"iconSpacing", 16);
    gPad     = FDFloat(d, @"sidePadding", 12);
    gBottom  = FDFloat(d, @"bottomMargin", 20);
    gHeight  = FDFloat(d, @"dockHeight", 82);
    gRadius  = FDFloat(d, @"cornerRadius", 30);
}

static CGFloat FDRadius(void) { return MIN(gRadius, gHeight / 2.0); }

static BOOL FDInsideDock(UIView *v) {
    for (UIView *a = v.superview; a; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:@"SBDockView"]) return YES;
    }
    return NO;
}

static UIView *FDDockOf(UIView *v) {
    for (UIView *a = v; a; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:@"SBDockView"]) return a;
    }
    return nil;
}

// Dock width follows the icons: icons + gaps + padding on both sides.
static CGRect FDTargetFrame(UIView *dock) {
    CGRect p = dock.superview.bounds;
    if (CGRectIsEmpty(p)) return dock.frame;
    CGFloat n = MAX(1, gCount);
    CGFloat w = n * gIconW + (n - 1) * gGap + gPad * 2.0;
    w = MIN(w, p.size.width - 20.0);
    return CGRectMake(CGRectGetMidX(p) - w / 2.0, CGRectGetMaxY(p) - gBottom - gHeight, w, gHeight);
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

// Put the dock icons at an even distance from each other.
static BOOL FDIsIconView(UIView *v) {
    NSString *cn = NSStringFromClass(v.class);
    return [cn containsString:@"IconView"] && ![cn containsString:@"List"] && ![cn containsString:@"Label"];
}

static void FDSpaceIcons(UIView *list) {
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    for (UIView *v in list.subviews) {
        if (FDIsIconView(v) && !v.hidden) [icons addObject:v];
    }
    if (!icons.count) return;
    [icons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.center.x < b.center.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSInteger n = (NSInteger)icons.count;
    CGFloat iw = MAX(40.0, MIN(90.0, icons.firstObject.bounds.size.width));

    if (n != gCount || fabs(iw - gIconW) > 0.5) {
        gCount = n; gIconW = iw;
        UIView *dock = FDDockOf(list);
        if (dock) dispatch_async(dispatch_get_main_queue(), ^{ [dock.superview setNeedsLayout]; [dock setNeedsLayout]; });
    }
    CGFloat total = n * iw + (n - 1) * gGap;
    CGFloat startX = (list.bounds.size.width - total) / 2.0;
    for (NSInteger i = 0; i < n; i++) {
        UIView *ic = icons[i];
        ic.center = CGPointMake(startX + iw / 2.0 + i * (iw + gGap), ic.center.y);
    }
}

static void FDMaybeSpace(UIView *list) {
    if (!gEnabled) return;
    if ([NSStringFromClass(list.class) containsString:@"Dock"] || FDInsideDock(list)) FDSpaceIcons(list);
}

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
    CGFloat radius = gEnabled ? FDRadius() : 0;
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

// Round a dock material and make LiquidAss redraw its glass with the rounded shape.
static void FDPrepareMaterial(UIView *v) {
    CGFloat r = FDRadius();
    FDRound(v, r);
    FDFixBorders(v, r, 0);
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
// New background views are rounded as soon as they are added.
- (void)didAddSubview:(UIView *)sub {
    %orig;
    if (gEnabled) FDStyleBackground((UIView *)self, FDRadius(), 0);
}
%end

// SpringBoard recreates the dock material after unlocking. Round it as soon as it appears,
// before LiquidAss draws its glass, and again shortly after.
%hook MTMaterialView
- (void)didMoveToSuperview {
    %orig;
    UIView *v = (UIView *)self;
    if (gEnabled && v.superview && FDInsideDock(v)) FDPrepareMaterial(v);
}
- (void)didMoveToWindow {
    %orig;
    UIView *v = (UIView *)self;
    if (gEnabled && v.window && FDInsideDock(v)) {
        FDPrepareMaterial(v);
        __weak UIView *wv = v;
        for (NSNumber *delay in @[@0.05, @0.3, @1.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIView *sv = wv;
                if (!sv || !gEnabled || !sv.window) return;
                FDPrepareMaterial(sv);
                [sv setNeedsLayout];
                for (UIView *sub in sv.subviews) [sub setNeedsLayout];
            });
        }
    }
}
- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    if (gEnabled && v.bounds.size.width > 160.0 && FDInsideDock(v)) FDPrepareMaterial(v);
}
%end

%hook SBIconListView
- (void)layoutIconsNow {
    %orig;
    FDMaybeSpace((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    FDMaybeSpace((UIView *)self);
}
%end

%ctor {
    FDLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        FDPrefsChanged, CFSTR(FD_NOTIFY), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
