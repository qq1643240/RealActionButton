#import "ABMCPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"

static NSString *titleForActionID(NSString *actionID) {
    if (!actionID || [actionID isEqualToString:@"none"]) return @"无操作";
    CFPropertyListRef rawMeta = CFPreferencesCopyValue(CFSTR("actionMetadata"), (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *metadata = rawMeta ? (__bridge_transfer NSDictionary *)rawMeta : nil;
    NSDictionary *meta = [metadata isKindOfClass:[NSDictionary class]] ? metadata[actionID] : nil;
    NSString *custom = [meta isKindOfClass:[NSDictionary class]] ? meta[@"title"] : nil;
    if (custom.length && ![custom isEqualToString:actionID]) return custom;
    NSDictionary *titles = @{@"default":@"系统默认", @"flashlight":@"切换手电筒", @"camera":@"打开相机", @"silent":@"切换静音模式", @"screenshot":@"截屏", @"lock":@"锁定设备", @"respring":@"注销弹簧板", @"url:weixin://scanqrcode":@"微信扫一扫", @"url:weixin://widget/pay":@"微信付款码", @"url:alipay://platformapi/startapp?appId=10000007":@"支付宝扫码", @"url:alipay://platformapi/startapp?appId=20000056":@"支付宝付款"};
    NSString *fixed = titles[actionID];
    if (fixed) return fixed;
    if ([actionID hasPrefix:@"app:"]) return meta[@"appName"] ?: [actionID substringFromIndex:4];
    if ([actionID hasPrefix:@"shortcut:"]) return [actionID substringFromIndex:9];
    if ([actionID hasPrefix:@"appshortcut:"]) { NSArray *parts=[[actionID substringFromIndex:12] componentsSeparatedByString:@"|"]; return parts.count>2 ? parts[2] : @"快捷方式"; }
    return actionID.length ? actionID : @"无操作";
}

static UIImage *iconForActionID(__unused NSString *actionID) {
    return [UIImage systemImageNamed:@"hand.tap"];
}

@implementation ABMCPreferences

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        PSSpecifier *actions = [PSSpecifier groupSpecifierWithName:@"操作"];
        [actions setProperty:@"设置点击、双击和长按。左滑动作可修改；已选择动作可删除。" forKey:@"footerText"];
        [specs addObject:actions];
        NSArray *items = @[@[@"单击动作", @"singleClickAction", @"default"], @[@"双击动作", @"doubleClickAction", @"none"], @[@"长按动作", @"longPressAction", @"default"]];
        for (NSArray *item in items) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:item[0] target:self set:NULL get:@selector(getActionValue:) detail:NSClassFromString(@"ABMCActionListController") cell:PSLinkCell edit:Nil];
            [spec setProperty:item[1] forKey:@"key"];
            [spec setProperty:item[2] forKey:@"default"];
            [spec setProperty:PREFS_DOMAIN forKey:@"defaults"];
            NSString *key = item[1];
            CFPropertyListRef rawValue = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            NSString *currentAction = rawValue ? (__bridge_transfer NSString *)rawValue : item[2];
            UIImage *icon = iconForActionID(currentAction.length ? currentAction : item[2]); if (icon) [spec setProperty:icon forKey:@"iconImage"];
            [specs addObject:spec];
        }
        _specifiers = specs;
    }
    return _specifiers;
}

- (id)getActionValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPropertyListRef value = key.length ? CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) : NULL;
    NSString *actionID = value ? (__bridge_transfer NSString *)value : [specifier propertyForKey:@"default"];
    return titleForActionID(actionID);
}

- (void)reloadSpecifiers {
    [super reloadSpecifiers];
    for (PSSpecifier *spec in _specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if (![key hasSuffix:@"Action"]) continue;
        CFStringRef value = (CFStringRef)CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSString *actionID = value ? (__bridge_transfer NSString *)value : [spec propertyForKey:@"default"];
        [spec setProperty:titleForActionID(actionID) forKey:@"cellValue"];
        UIImage *icon = iconForActionID(actionID); if (icon) [spec setProperty:icon forKey:@"iconImage"];
    }
}
@end
