#import "ABMCActionListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

typedef struct { NSString *actionID; NSString *title; } ABMCAction;

static const ABMCAction kBuiltInActions[] = {
    { @"default",    @"默认" },
    { @"flashlight", @"手电" },
    { @"camera",     @"相机" },
    { @"silent",      @"静音" },
    { @"screenshot", @"截屏" },
    { @"lock",       @"锁屏" },
    { @"respring",   @"重启" },
    { @"url:weixin://scanqrcode", @"微扫" },
    { @"url:weixin://widget/pay", @"微付" },
    { @"url:alipay://platformapi/startapp?appId=10000007", @"支扫" },
    { @"url:alipay://platformapi/startapp?appId=20000056", @"支付" },
    { @"none",       @"关闭" },
};

@implementation ABMCActionListController { NSString *_prefKey; NSString *_currentValue; }

- (void)viewDidLoad {
    [super viewDidLoad];
    PSSpecifier *parent = [self specifier];
    _prefKey = [parent propertyForKey:@"key"];
    NSString *fallback = [parent propertyForKey:@"default"] ?: @"none";
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_prefKey, (__bridge CFStringRef)PREFS_DOMAIN);
    _currentValue = value ? (__bridge_transfer NSString *)value : fallback;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"操作"]];
        NSUInteger count = sizeof(kBuiltInActions) / sizeof(kBuiltInActions[0]);
        for (NSUInteger i = 0; i < count; i++) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:kBuiltInActions[i].title target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
            [spec setProperty:kBuiltInActions[i].actionID forKey:@"actionID"];
            spec->action = @selector(selectAction:);
            [specs addObject:spec];
        }
        PSSpecifier *custom = [PSSpecifier groupSpecifierWithName:@"自设"];
        [custom setProperty:@"可按 App 的 Bundle ID、快捷指令名称或 URL / URL Scheme 执行操作。" forKey:@"footerText"];
        [specs addObject:custom];
        NSArray *items = @[@[@"应用…", @"customApp"], @[@"指令…", @"customShortcut"], @[@"网址…", @"customURL"]];
        for (NSArray *item in items) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:item[0] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
            [spec setProperty:item[1] forKey:@"actionID"];
            spec->action = @selector(selectAction:);
            [specs addObject:spec];
        }
        _specifiers = specs;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    NSString *actionID = [[self specifierAtIndexPath:indexPath] propertyForKey:@"actionID"];
    BOOL selected = actionID && ((![actionID hasPrefix:@"custom"] && [_currentValue isEqualToString:actionID]) ||
        ([actionID isEqualToString:@"customApp"] && [_currentValue hasPrefix:@"app:"]) ||
        ([actionID isEqualToString:@"customShortcut"] && [_currentValue hasPrefix:@"shortcut:"]) ||
        ([actionID isEqualToString:@"customURL"] && [_currentValue hasPrefix:@"url:"]));
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)selectAction:(PSSpecifier *)specifier {
    NSString *actionID = [specifier propertyForKey:@"actionID"];
    if ([actionID isEqualToString:@"customApp"]) [self promptForValueWithTitle:@"打开 App" message:@"请输入 App Bundle ID（例如 com.apple.Music）：" prefix:@"app:" keyboard:UIKeyboardTypeDefault];
    else if ([actionID isEqualToString:@"customShortcut"]) [self promptForValueWithTitle:@"运行快捷指令" message:@"请输入 Siri 快捷指令名称：" prefix:@"shortcut:" keyboard:UIKeyboardTypeDefault];
    else if ([actionID isEqualToString:@"customURL"]) [self promptForValueWithTitle:@"打开 URL" message:@"请输入 URL 或 URL Scheme：" prefix:@"url:" keyboard:UIKeyboardTypeURL];
    else [self saveAction:actionID];
}

- (void)promptForValueWithTitle:(NSString *)title message:(NSString *)message prefix:(NSString *)prefix keyboard:(UIKeyboardType)keyboard {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = keyboard;
        if ([self->_currentValue hasPrefix:prefix]) field.text = [self->_currentValue substringFromIndex:prefix.length];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!value.length) return;
        if ([prefix isEqualToString:@"url:"]) {
            NSURL *url = [NSURL URLWithString:value];
            if (!url || !url.scheme.length) { [self showInvalidURL]; return; }
        }
        [self saveAction:[prefix stringByAppendingString:value]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showInvalidURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"URL 无效" message:@"请输入包含有效 URL Scheme 的地址。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveAction:(NSString *)actionID {
    _currentValue = actionID;
    CFPreferencesSetAppValue((__bridge CFStringRef)_prefKey, (__bridge CFPropertyListRef)actionID, (__bridge CFStringRef)PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
    [self.table reloadData];
}
@end
