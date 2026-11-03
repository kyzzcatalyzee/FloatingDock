#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define FD_DOMAIN @"com.zilvyn.floatdock"

#pragma mark - Dock preview

// App icon from the system (private API, works inside Settings). Falls back to a simple icon.
static UIImage *FDAppIcon(NSString *bundleID, NSString *symbol, UIColor *color) {
    Class c = [UIImage class];
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([c respondsToSelector:sel]) {
        UIImage *(*send)(id, SEL, id, int, CGFloat) = (UIImage *(*)(id, SEL, id, int, CGFloat))objc_msgSend;
        UIImage *img = send(c, sel, bundleID, 2, [UIScreen mainScreen].scale);
        if (img) return img;
    }
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 60, 60) cornerRadius:13.5] fill];
        UIImage *sym = [[UIImage systemImageNamed:symbol] imageWithTintColor:UIColor.whiteColor
                                                               renderingMode:UIImageRenderingModeAlwaysOriginal];
        [sym drawInRect:CGRectMake(14, 14, 32, 32)];
    }];
}

@interface FDPreviewView : UIView
- (void)reloadWithOverrideKey:(NSString *)key value:(id)value;
@end

@implementation FDPreviewView {
    UIView *_platter;
    NSArray<UIImageView *> *_icons;
    BOOL _on;
    CGFloat _gap, _pad, _height, _radius;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;

        _platter = [[UIView alloc] init];
        _platter.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:1 alpha:0.14] : [UIColor colorWithWhite:0 alpha:0.10];
        }];
        _platter.layer.borderWidth = 0.5;
        _platter.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.35].CGColor;
        [self addSubview:_platter];

        NSArray *defs = @[
            @[@"com.apple.mobilephone", @"phone.fill", [UIColor systemGreenColor]],
            @[@"com.apple.mobilesafari", @"safari", [UIColor systemBlueColor]],
            @[@"com.apple.MobileSMS", @"message.fill", [UIColor systemGreenColor]],
            @[@"com.apple.Music", @"music.note", [UIColor systemPinkColor]],
        ];
        NSMutableArray *icons = [NSMutableArray array];
        for (NSArray *d in defs) {
            UIImageView *iv = [[UIImageView alloc] initWithImage:FDAppIcon(d[0], d[1], d[2])];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            [self addSubview:iv];
            [icons addObject:iv];
        }
        _icons = icons;
        [self reloadWithOverrideKey:nil value:nil];
    }
    return self;
}

- (void)reloadWithOverrideKey:(NSString *)key value:(id)value {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:FD_DOMAIN];
    id (^get)(NSString *, id) = ^id(NSString *k, id def) {
        if (key && [k isEqualToString:key] && value) return value;
        id v = [d objectForKey:k];
        return v ?: def;
    };
    _on     = [get(@"enabled", @YES) boolValue];
    _gap    = [get(@"iconSpacing", @16) doubleValue];
    _pad    = [get(@"sidePadding", @12) doubleValue];
    _height = [get(@"dockHeight", @82) doubleValue];
    _radius = [get(@"cornerRadius", @30) doubleValue];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat iw = 60.0;
    CGFloat dockW = 4 * iw + 3 * _gap + 2 * _pad;
    CGFloat dockH = MAX(_height, 40);
    CGFloat sc = MIN(1.0, MIN((self.bounds.size.width - 28.0) / dockW, (self.bounds.size.height - 28.0) / dockH));
    CGFloat w = dockW * sc, h = dockH * sc;
    CGFloat x = (self.bounds.size.width - w) / 2.0, y = (self.bounds.size.height - h) / 2.0;

    _platter.frame = CGRectMake(x, y, w, h);
    _platter.layer.cornerRadius = MIN(_radius, dockH / 2.0) * sc;
    _platter.layer.cornerCurve = kCACornerCurveContinuous;

    for (NSUInteger i = 0; i < _icons.count; i++) {
        _icons[i].frame = CGRectMake(x + (_pad + i * (iw + _gap)) * sc, y + (h - iw * sc) / 2.0, iw * sc, iw * sc);
    }
    self.alpha = _on ? 1.0 : 0.45;
}

@end

#pragma mark - Settings page

@interface FDRootListController : PSListController
@end

@implementation FDRootListController {
    UIView *_header;
    FDPreviewView *_preview;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (UITableView *)fdTable {
    return [self valueForKey:@"table"];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _header = [[UIView alloc] init];
    UILabel *title = [[UILabel alloc] init];
    title.text = @"DOCK PREVIEW";
    title.font = [UIFont systemFontOfSize:13];
    title.textColor = [UIColor secondaryLabelColor];
    title.tag = 11;
    [_header addSubview:title];

    _preview = [[FDPreviewView alloc] init];
    _preview.tag = 12;
    [_header addSubview:_preview];

    [self fdLayoutHeader];
}

- (void)fdLayoutHeader {
    UITableView *table = [self fdTable];
    if (!table || !_header) return;
    CGFloat w = table.bounds.size.width;
    if (w <= 0) return;
    const CGFloat margin = 20.0;
    _header.frame = CGRectMake(0, 0, w, 24 + 150 + 14);
    [_header viewWithTag:11].frame = CGRectMake(margin + 16, 6, w - 2 * margin - 16, 18);
    _preview.frame = CGRectMake(margin, 28, w - 2 * margin, 150);
    if (table.tableHeaderView != _header) table.tableHeaderView = _header;
    else table.tableHeaderView = _header; // refresh the header height
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *table = [self fdTable];
    if (table && fabs(_header.frame.size.width - table.bounds.size.width) > 0.5) [self fdLayoutHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_preview reloadWithOverrideKey:nil value:nil];
}

// Every change in the settings (sliders, switch) is shown in the preview right away.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    [_preview reloadWithOverrideKey:[specifier propertyForKey:@"key"] value:value];
}

- (void)resetValues {
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:FD_DOMAIN];
    [p setFloat:16 forKey:@"iconSpacing"]; [p setFloat:12 forKey:@"sidePadding"];
    [p setFloat:20 forKey:@"bottomMargin"];
    [p setFloat:82 forKey:@"dockHeight"];
    [p setFloat:30 forKey:@"cornerRadius"];
    [p synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zilvyn.floatdock/prefschanged"), NULL, NULL, YES);
    [self reloadSpecifiers];
    [_preview reloadWithOverrideKey:nil value:nil];
}

@end
