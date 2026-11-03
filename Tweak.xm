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
static void FDPrepareMaterial(UIView *v);
static void FDForEachDockMaterialFwd(UIView *root, int depth, void (^block)(UIView *));

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

// Dock width is fixed to a full dock (at least 4 icon slots), like the iPhone X dock:
// removing icons does not shrink it, the remaining icons stay centered.
static CGRect FDTargetFrame(UIView *dock) {
    CGRect p = dock.superview.bounds;
    if (CGRectIsEmpty(p)) return dock.frame;
    CGFloat n = MAX(4, gCount);
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

// Width of the icon picture itself (60 pt). The icon view can be wider (label area),
// and that differs between the iPhone X and the home button iPhone layout.
static CGFloat FDIconImageWidth(UIView *icon) {
    @try {
        id iv = [icon valueForKey:@"iconImageView"];
        if ([iv isKindOfClass:[UIView class]] && ((UIView *)iv).bounds.size.width > 20.0)
            return ((UIView *)iv).bounds.size.width;
    } @catch (__unused NSException *ex) {}
    for (UIView *sub in icon.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"IconImageView"] && sub.bounds.size.width > 20.0)
            return sub.bounds.size.width;
    }
    return icon.bounds.size.width;
}

static void FDSpaceIcons(UIView *list) {
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    for (UIView *v in list.subviews) {
        if (!FDIsIconView(v) || v.hidden || v.alpha < 0.01) continue;
        if (!CGRectIntersectsRect(v.frame, list.bounds)) continue;
        [icons addObject:v];
    }
    if (!icons.count) return;
    [icons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.center.x < b.center.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSInteger n = MIN((NSInteger)icons.count, 6);
    CGFloat iw = MAX(54.0, MIN(66.0, FDIconImageWidth(icons.firstObject)));

    if (n != gCount || fabs(iw - gIconW) > 0.5) {
        gCount = n; gIconW = iw;
        UIView *dock = FDDockOf(list);
        if (dock) dispatch_async(dispatch_get_main_queue(), ^{ [dock.superview setNeedsLayout]; [dock setNeedsLayout]; });
    }
    CGFloat total = n * iw + (n - 1) * gGap;
    CGFloat startX = (list.bounds.size.width - total) / 2.0;
    // Vertically: the exact middle of the dock (not of the icon list, which starts a few points lower).
    UIView *dockView = FDDockOf(list);
    CGFloat cy = dockView ? (dockView.bounds.size.height / 2.0 - list.frame.origin.y) : 0;
    for (NSInteger i = 0; i < n; i++) {
        UIView *ic = icons[i];
        ic.center = CGPointMake(startX + iw / 2.0 + i * (iw + gGap), dockView ? cy : ic.center.y);
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

// On the home button iPhone layout SpringBoard makes the dock material ~56pt wider and ~96pt
// taller than the dock itself. Make it exactly as big as the dock so the floating look is right.
static void FDFitMaterials(UIView *dock) {
    CGRect want = CGRectMake(0, 0, dock.bounds.size.width, dock.bounds.size.height);
    FDForEachDockMaterialFwd(dock, 0, ^(UIView *m) {
        if (m.superview == dock && !CGRectEqualToRect(m.frame, want)) m.frame = want;
    });
    // The thin straight highlight line at the top of the stock dock does not fit a rounded dock.
    for (UIView *v in dock.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"SBHighlightView"]) v.hidden = gEnabled;
    }
}

// Small log so we can compare the two device subtypes: /var/mobile/Library/FloatDock/log.txt
#define FD_LOGDIR  @"/var/mobile/Library/FloatDock"
#define FD_LOGFILE @"/var/mobile/Library/FloatDock/log.txt"
static void FDLog(NSString *line) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:FD_LOGDIR withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *at = [fm attributesOfItemAtPath:FD_LOGFILE error:nil];
    if ([at fileSize] > 30000) [fm removeItemAtPath:FD_LOGFILE error:nil];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:FD_LOGFILE];
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (!h) { [d writeToFile:FD_LOGFILE atomically:NO]; return; }
    [h seekToEndOfFile]; [h writeData:d]; [h closeFile];
}

static void FDDumpDock(UIView *dock) {
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 5.0) return;
    last = now;
    NSMutableString *m = [NSMutableString string];
    [m appendFormat:@"==== %@ model=%@ screen=%@ ====\n", [NSDate date],
        [[UIDevice currentDevice] model], NSStringFromCGRect([UIScreen mainScreen].bounds)];
    [m appendFormat:@"dock=%@ frame=%@ bounds=%@ super=%@ superBounds=%@\n", NSStringFromClass(dock.class),
        NSStringFromCGRect(dock.frame), NSStringFromCGRect(dock.bounds),
        NSStringFromClass(dock.superview.class), NSStringFromCGRect(dock.superview.bounds)];
    [m appendFormat:@"prefs gap=%.0f pad=%.0f bottom=%.0f height=%.0f radius=%.0f count=%ld iconW=%.1f target=%@\n",
        gGap, gPad, gBottom, gHeight, gRadius, (long)gCount, gIconW, NSStringFromCGRect(FDTargetFrame(dock))];
    for (UIView *v in dock.subviews) {
        [m appendFormat:@"  sub %@ frame=%@ r=%.1f hidden=%d alpha=%.2f\n", NSStringFromClass(v.class),
            NSStringFromCGRect(v.frame), v.layer.cornerRadius, v.hidden, v.alpha];
        if ([NSStringFromClass(v.class) containsString:@"IconListView"]) {
            for (UIView *ic in v.subviews) {
                [m appendFormat:@"    icon %@ frame=%@ imgW=%.1f hidden=%d alpha=%.2f\n", NSStringFromClass(ic.class),
                    NSStringFromCGRect(ic.frame), FDIconImageWidth(ic), ic.hidden, ic.alpha];
            }
        }
    }
    FDForEachDockMaterialFwd(dock, 0, ^(UIView *mat) {
        [m appendFormat:@"  material frame=%@ r=%.1f super=%@\n", NSStringFromCGRect(mat.frame),
            mat.layer.cornerRadius, NSStringFromClass(mat.superview.class)];
        for (UIView *g in mat.superview.subviews) {
            if ([NSStringFromClass(g.class) containsString:@"LGLiveBackdropView"])
                [m appendFormat:@"  glass frame=%@ r=%.1f\n", NSStringFromCGRect(g.frame), g.layer.cornerRadius];
        }
    });
    FDLog(m);
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
    if (!gEnabled) { FDFitMaterials(dock); return; }

    FDDumpDock(dock);
    CGRect target = FDTargetFrame(dock);
    if (!CGRectEqualToRect(dock.frame, target)) {
        gAdjusting = YES;
        dock.frame = target;
        [dock setNeedsLayout];
        [dock layoutIfNeeded];
        FDRelayoutIcons(dock, 0);
        gAdjusting = NO;
    }
    FDFitMaterials(dock);
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

// LiquidAss puts its glass NEXT to the material (same parent), and copies the material
// corner radius only when it syncs. If the glass kept radius 0 it shows as a square.
static void FDFixGlass(UIView *material) {
    UIView *parent = material.superview;
    if (!parent) return;
    CGFloat r = FDRadius();
    BOOL stale = NO;
    for (UIView *g in parent.subviews) {
        if (![NSStringFromClass(g.class) containsString:@"LGLiveBackdropView"]) continue;
        if (fabs(g.layer.cornerRadius - r) > 0.5) stale = YES;
    }
    if (stale) {
        // Setting the same frame makes LiquidAss sync the glass with the material again.
        CGRect f = material.frame;
        material.frame = f;
    }
}

// Round a dock material and make LiquidAss redraw its glass with the rounded shape.
static void FDPrepareMaterial(UIView *v) {
    CGFloat r = FDRadius();
    FDRound(v, r);
    FDFixBorders(v, r, 0);
}

static void FDForEachDockMaterial(UIView *root, int depth, void (^block)(UIView *)) {
    if (depth > 6) return;
    for (UIView *v in root.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"MTMaterialView"]) block(v);
        FDForEachDockMaterial(v, depth + 1, block);
    }
}
static void FDForEachDockMaterialFwd(UIView *root, int depth, void (^block)(UIView *)) {
    FDForEachDockMaterial(root, depth, block);
}

// Re-round everything in every dock and re-sync the glass.
static void FDFixAllDocks(void) {
    if (!gEnabled) return;
    for (UIView *dock in gDocks.allObjects) {
        FDStyleBackground(dock, FDRadius(), 0);
        FDForEachDockMaterial(dock, 0, ^(UIView *m) {
            FDPrepareMaterial(m);
            FDFixGlass(m);
        });
    }
}

// After the screen is unlocked (passcode or Touch ID) fix the dock a few times,
// because SpringBoard rebuilds it in several steps.
static void FDScheduleFixes(void) {
    for (NSNumber *delay in @[@0.05, @0.25, @0.6, @1.2, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ FDFixAllDocks(); });
    }
}

static void FDLockChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ FDScheduleFixes(); });
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
    FDForEachDockMaterial((UIView *)self, 0, ^(UIView *m) { FDFixGlass(m); });
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
- (void)setFrame:(CGRect)frame {
    UIView *v = (UIView *)self;
    if (gEnabled && v.superview && [NSStringFromClass(v.superview.class) isEqualToString:@"SBDockView"]) {
        frame = CGRectMake(0, 0, v.superview.bounds.size.width, v.superview.bounds.size.height);
    }
    %orig(frame);
}
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
                FDFixGlass(sv);
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

// Whoever sets the corner radius of a dock material (SpringBoard, MaterialKit, ...), keep ours.
%hook CALayer
- (void)setCornerRadius:(CGFloat)radius {
    if (gEnabled) {
        static Class materialClass;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ materialClass = NSClassFromString(@"MTMaterialView"); });
        id d = self.delegate;
        if (materialClass && d && [d isKindOfClass:materialClass] && FDInsideDock((UIView *)d)) {
            radius = FDRadius();
        }
    }
    %orig(radius);
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
    CFNotificationCenterRef dc = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(dc, NULL, FDPrefsChanged, CFSTR(FD_NOTIFY), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    for (NSString *n in @[@"com.apple.springboard.lockstate",
                          @"com.apple.springboard.lockcomplete",
                          @"com.apple.springboard.hasBlankedScreen"]) {
        CFNotificationCenterAddObserver(dc, NULL, FDLockChanged, (__bridge CFStringRef)n, NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
    }
}
