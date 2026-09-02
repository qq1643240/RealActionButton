#import "ABMCPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"

static NSString *titleForActionID(NSString *actionID) {
    if (!actionID || [actionID isEqualToString:@"none"]) return @"关闭";
    CFPropertyListRef rawMeta = CFPreferencesCopyValue(CFSTR("actionMetadata"), (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *metadata = rawMeta ? (__bridge_transfer NSDictionary *)rawMeta : nil;
    NSDictionary *meta = [metadata isKindOfClass:[NSDictionary class]] ? metadata[actionID] : nil;
    NSString *custom = [meta isKindOfClass:[NSDictionary class]] ? meta[@"title"] : nil;
    if (custom.length) return custom;
    if ([actionID isEqualToString:@"default"]) return @"系统默认";
    if ([actionID isEqualToString:@"flashlight"]) return @"手电筒";
    if ([actionID isEqualToString:@"camera"]) return @"相机";
    if ([actionID isEqualToString:@"silent"]) return @"静音模式";
    if ([actionID isEqualToString:@"screenshot"]) return @"屏幕截图";
    if ([actionID isEqualToString:@"lock"]) return @"锁定屏幕";
    if ([actionID isEqualToString:@"controlCenter"]) return @"控制中心";
    if ([actionID isEqualToString:@"notificationCenter"]) return @"通知中心";
    if ([actionID isEqualToString:@"spotlight"]) return @"聚焦搜索";
    if ([actionID isEqualToString:@"screenRecord"]) return @"屏幕录制";
    if ([actionID isEqualToString:@"mediaPlayPause"]) return @"播放暂停";
    if ([actionID isEqualToString:@"mediaPrevious"]) return @"上一首歌";
    if ([actionID isEqualToString:@"mediaNext"]) return @"下一首歌";
    if ([actionID isEqualToString:@"closeApps"]) return @"关闭应用";
    if ([actionID isEqualToString:@"respring"]) return @"重启桌面";
    if ([actionID isEqualToString:@"url:weixin://scanqrcode"]) return @"微信扫一扫";
    if ([actionID isEqualToString:@"url:weixin://widget/pay"]) return @"微信付款码";
    if ([actionID isEqualToString:@"url:alipay://platformapi/startapp?appId=10000007"]) return @"支付宝扫一扫";
    if ([actionID isEqualToString:@"url:alipay://platformapi/startapp?appId=20000056"]) return @"支付宝付款码";
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", ([meta[@"appName"] length] ? meta[@"appName"] : [actionID substringFromIndex:4])];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"快捷指令：%@", [actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"appshortcut:"]) { NSArray *parts=[[actionID substringFromIndex:12] componentsSeparatedByString:@"|"]; return parts.count>2 ? parts[2] : @"快捷方式"; }
    if ([actionID hasPrefix:@"customURL:"]) return [NSString stringWithFormat:@"链接：%@", [actionID substringFromIndex:10]];
    return actionID;
}

@implementation ABMCPreferences

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        PSSpecifier *actions = [PSSpecifier groupSpecifierWithName:@"操作"];
        [actions setProperty:@"设置点击、双击和长按。" forKey:@"footerText"];
        [specs addObject:actions];
        NSArray *items = @[@[@"单击动作", @"singleClickAction", @"default"], @[@"双击动作", @"doubleClickAction", @"none"], @[@"长按动作", @"longPressAction", @"default"]];
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
            CFStringRef value = (CFStringRef)CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            NSString *actionID = value ? (__bridge_transfer NSString *)value : [spec propertyForKey:@"default"];
            [spec setProperty:titleForActionID(actionID) forKey:@"cellValue"];
        }
    }
}
@end
