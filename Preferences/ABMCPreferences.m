#import "ABMCPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static NSString *titleForActionID(NSString *actionID) {
    if (!actionID || [actionID isEqualToString:@"none"]) return @"无操作";
    if ([actionID isEqualToString:@"default"]) return @"系统默认";
    if ([actionID isEqualToString:@"flashlight"]) return @"手电筒";
    if ([actionID isEqualToString:@"camera"]) return @"相机";
    if ([actionID isEqualToString:@"silent"]) return @"静音模式";
    if ([actionID isEqualToString:@"screenshot"]) return @"截屏";
    if ([actionID isEqualToString:@"lock"]) return @"锁定屏幕";
    if ([actionID isEqualToString:@"respring"]) return @"重启 SpringBoard";
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"App：%@", [actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"快捷指令：%@", [actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"url:"]) return [NSString stringWithFormat:@"URL：%@", [actionID substringFromIndex:4]];
    return actionID;
}

static void calibrationDoneCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [(__bridge ABMCPreferences *)observer calibrationDidFinish];
}

@implementation ABMCPreferences { BOOL _waitingForCalibration; }

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        PSSpecifier *actions = [PSSpecifier groupSpecifierWithName:@"操作按钮"];
        [actions setProperty:@"分别设置操作按钮的单击、双击和长按动作。长按选择“系统默认”时，完全保留 iOS 原生长按行为。" forKey:@"footerText"];
        [specs addObject:actions];
        NSArray *items = @[@[@"单击动作", @"singleClickAction", @"default"], @[@"双击动作", @"doubleClickAction", @"none"], @[@"长按动作", @"longPressAction", @"default"]];
        for (NSArray *item in items) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:item[0] target:self set:NULL get:NULL detail:NSClassFromString(@"ABMCActionListController") cell:PSLinkCell edit:Nil];
            [spec setProperty:item[1] forKey:@"key"];
            [spec setProperty:item[2] forKey:@"default"];
            [spec setProperty:PREFS_DOMAIN forKey:@"defaults"];
            [specs addObject:spec];
        }
        PSSpecifier *timing = [PSSpecifier groupSpecifierWithName:@"点击间隔"];
        [timing setProperty:@"在触发单击前等待第二次点击的时间。数值越低响应越快，但双击越难识别。可使用校准自动检测适合你的双击速度。" forKey:@"footerText"];
        [specs addObject:timing];
        PSSpecifier *timeout = [PSSpecifier preferenceSpecifierNamed:@"点击等待时间" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSSliderCell edit:Nil];
        [timeout setProperty:@"clickTimeout" forKey:@"key"];
        [timeout setProperty:@0.5 forKey:@"min"];
        [timeout setProperty:@2.0 forKey:@"max"];
        [timeout setProperty:@1.5 forKey:@"default"];
        [timeout setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [timeout setProperty:PREFS_NOTIFICATION forKey:@"PostNotification"];
        [timeout setProperty:@YES forKey:@"showValue"];
        [specs addObject:timeout];
        PSSpecifier *calibrate = [PSSpecifier preferenceSpecifierNamed:@"校准双击" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        calibrate->action = @selector(startCalibration);
        [specs addObject:calibrate];
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, calibrationDoneCallback, CFSTR("com.huynguyen.actionbuttonmulticlick/calibrationDone"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, CFSTR("com.huynguyen.actionbuttonmulticlick/calibrationDone"), NULL);
}

- (void)startCalibration {
    _waitingForCalibration = YES;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"校准双击" message:@"请以你自然的双击速度连续按两次操作按钮。\n\n系统会自动调整点击等待时间。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { self->_waitingForCalibration = NO; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.huynguyen.actionbuttonmulticlick/startCalibration"), NULL, NULL, YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)calibrationDidFinish {
    if (!_waitingForCalibration) return;
    _waitingForCalibration = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
        CFPropertyListRef interval = CFPreferencesCopyAppValue(CFSTR("lastCalibrationInterval"), (__bridge CFStringRef)PREFS_DOMAIN);
        CFPropertyListRef timeout = CFPreferencesCopyAppValue(CFSTR("lastCalibrationTimeout"), (__bridge CFStringRef)PREFS_DOMAIN);
        NSString *intervalString = interval ? (__bridge_transfer NSString *)interval : @"?";
        NSNumber *timeoutValue = timeout ? (__bridge_transfer NSNumber *)timeout : @(1.5);
        NSString *message = [NSString stringWithFormat:@"你的双击间隔：%@ 秒\n点击等待时间已设为：%.2f 秒（间隔 + 0.3 秒缓冲）", intervalString, timeoutValue.doubleValue];
        UIAlertController *result = [UIAlertController alertControllerWithTitle:@"校准完成" message:message preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
        [self reloadSpecifiers];
    });
}

- (void)reloadSpecifiers {
    [super reloadSpecifiers];
    for (PSSpecifier *spec in _specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if ([key hasSuffix:@"Action"]) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
            CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN);
            NSString *actionID = value ? (__bridge_transfer NSString *)value : [spec propertyForKey:@"default"];
            [spec setProperty:titleForActionID(actionID) forKey:@"cellValue"];
        }
    }
}
@end
