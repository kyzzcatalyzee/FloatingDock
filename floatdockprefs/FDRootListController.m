#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

#define FD_DOMAIN @"com.zilvyn.floatdock"

@interface FDRootListController : PSListController
@end

@implementation FDRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
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
}

@end
