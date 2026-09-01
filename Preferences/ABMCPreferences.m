#import "ABMCPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"

static NSString *titleForActionID(NSString *actionID) {
    if (!actionID || [actionID isEqualToString:@"none"]) return @"关闭";
    if ([actionID isEqualToString:@"default"]) return @"默认";
    if ([actionID isEqualToString:@"flashlight"]) return @"手电";
    if ([actionID isEqualToString:@"camera"]) return @"相机";
    if ([actionID isEqualToString:@"silent"]) return @"静音";
    if ([actionID isEqualToString:@"screenshot"]) return @"截屏";
    if ([actionID isEqualToString:@"lock"]) return @"锁屏";
    if ([actionID isEqualToString:@"controlCenter"]) return @"控制中心";
    if ([actionID isEqualToString:@"notificationCenter"]) return @"通知中心";
    if ([actionID isEqualToString:@"spotlight"]) return @"聚焦";
    if ([actionID isEqualToString:@"screenRecord"]) return @"录屏";
    if ([actionID isEqualToString:@"mediaPlayPause"]) return @"播放";
    if ([actionID isEqualToString:@"mediaPrevious"]) return @"上一首";
    if ([actionID isEqualToString:@"mediaNext"]) return @"下一首";
    if ([actionID isEqualToString:@"closeApps"]) return @"关应用";
    if ([actionID isEqualToString:@"respring"]) return @"重启";
    if ([actionID isEqualToString:@"url:weixin://scanqrcode"]) return @"微信扫一扫";
    if ([actionID isEqualToString:@"url:weixin://widget/pay"]) return @"微信付款码";
    if ([actionID isEqualToString:@"url:alipay://platformapi/startapp?appId=10000007"]) return @"支付宝扫一扫";
    if ([actionID isEqualToString:@"url:alipay://platformapi/startapp?appId=20000056"]) return @"支付宝付款码";
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", [actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"指令：%@", [actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"customURL:"]) return [NSString stringWithFormat:@"网址：%@", [actionID substringFromIndex:10]];
    if ([actionID hasPrefix:@"url:"]) return @"网址";
    return actionID;
}

@implementation ABMCPreferences

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        PSSpecifier *actions = [PSSpecifier groupSpecifierWithName:@"操作"];
        [actions setProperty:@"设置点击、双击和长按。" forKey:@"footerText"];
        [specs addObject:actions];
        NSArray *items = @[@[@"点击", @"singleClickAction", @"default"], @[@"双击", @"doubleClickAction", @"none"], @[@"长按", @"longPressAction", @"default"]];
        for (NSArray *item in items) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:item[0] target:self set:NULL get:NULL detail:NSClassFromString(@"ABMCActionListController") cell:PSLinkCell edit:Nil];
            [spec setProperty:item[1] forKey:@"key"];
            [spec setProperty:item[2] forKey:@"default"];
            [spec setProperty:PREFS_DOMAIN forKey:@"defaults"];
            [specs addObject:spec];
        }
        _specifiers = specs;
    }
    return _specifiers;
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
