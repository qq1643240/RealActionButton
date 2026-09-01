#import "ABMCActionListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static NSString *ABMCActionTitle(NSString *actionID) {
    NSDictionary *titles = @{
        @"default": @"默认", @"flashlight": @"手电", @"camera": @"相机",
        @"silent": @"静音", @"screenshot": @"截屏", @"lock": @"锁屏",
        @"respring": @"重启", @"controlCenter": @"控中", @"notificationCenter": @"通知",
        @"spotlight": @"聚焦", @"screenRecord": @"录屏", @"mediaPlayPause": @"播放",
        @"mediaPrevious": @"上曲", @"mediaNext": @"下曲", @"closeApps": @"关应",
        @"url:weixin://scanqrcode": @"微信扫一扫",
        @"url:weixin://widget/pay": @"微信付款码",
        @"url:alipay://platformapi/startapp?appId=10000007": @"支付宝扫一扫",
        @"url:alipay://platformapi/startapp?appId=20000056": @"支付宝付款码",
        @"none": @"关闭"
    };
    NSString *title = titles[actionID];
    if (title) return title;
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", [actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"指令：%@", [actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"customURL:"]) return [NSString stringWithFormat:@"网址：%@", [actionID substringFromIndex:10]];
    if ([actionID hasPrefix:@"url:"]) return [NSString stringWithFormat:@"网址：%@", [actionID substringFromIndex:4]];
    return actionID.length ? actionID : @"关闭";
}

static PSSpecifier *ABMCRow(NSString *title, NSString *actionID, id target) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title target:target set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
    [spec setProperty:actionID forKey:@"actionID"];
    NSDictionary *symbols = @{
        @"default": @"hand.tap", @"flashlight": @"flashlight.on.fill", @"camera": @"camera.fill",
        @"silent": @"speaker.slash.fill", @"screenshot": @"crop", @"controlCenter": @"switch.2",
        @"notificationCenter": @"bell.fill", @"spotlight": @"magnifyingglass", @"screenRecord": @"record.circle",
        @"lock": @"lock.fill", @"mediaPlayPause": @"playpause.fill", @"mediaPrevious": @"backward.fill",
        @"mediaNext": @"forward.fill", @"closeApps": @"rectangle.stack.fill", @"respring": @"arrow.clockwise",
        @"category:basic": @"hand.tap", @"category:apps": @"app.fill", @"category:shortcuts": @"bolt.fill",
        @"category:commands": @"list.bullet.rectangle", @"category:links": @"safari.fill", @"category:presets": @"link"
    };
    NSString *symbol = symbols[actionID];
    if (symbol) [spec setProperty:symbol forKey:@"symbolName"];
    spec->action = @selector(selectAction:);
    return spec;
}

@interface ABMCActionListController ()
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
@end

@implementation ABMCActionListController {
    NSString *_prefKey;
    NSString *_currentValue;
    NSString *_category;
}

- (instancetype)initWithPreferenceKey:(NSString *)preferenceKey category:(NSString *)category {
    self = [super init];
    if (self) {
        _prefKey = [preferenceKey copy];
        _category = [category copy];
        [self loadCurrentValueWithFallback:@"none"];
        self.title = _category.length ? [self categoryTitle] : @"选择动作";
    }
    return self;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    return [self initWithPreferenceKey:[specifier propertyForKey:@"key"] category:[specifier propertyForKey:@"category"]];
}

- (void)loadCurrentValueWithFallback:(NSString *)fallback {
    if (!_prefKey.length) {
        _currentValue = [fallback copy];
        return;
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_prefKey, (__bridge CFStringRef)PREFS_DOMAIN);
    _currentValue = value ? (__bridge_transfer NSString *)value : [fallback copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!_prefKey.length) {
        PSSpecifier *parent = [self specifier];
        _prefKey = [[parent propertyForKey:@"key"] copy];
        _category = [[parent propertyForKey:@"category"] copy];
        [self loadCurrentValueWithFallback:[parent propertyForKey:@"default"] ?: @"none"];
    }
    self.title = _category.length ? [self categoryTitle] : @"选择动作";
}

- (NSString *)categoryTitle {
    NSDictionary *titles = @{@"basic": @"基础", @"apps": @"应用", @"shortcuts": @"方式", @"commands": @"指令", @"links": @"链接", @"presets": @"预设"};
    return titles[_category] ?: @"选择动作";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        if (!_category.length) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"已选择"]];
            NSString *selectedTitle = [_currentValue isEqualToString:@"none"] ? @"未选择" : ABMCActionTitle(_currentValue);
            [specs addObject:ABMCRow(selectedTitle, @"__selected__", self)];
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"选择动作"]];
            NSArray *categories = @[@[@"基础", @"category:basic"], @[@"应用", @"category:apps"], @[@"方式", @"category:shortcuts"], @[@"指令", @"category:commands"], @[@"链接", @"category:links"], @[@"预设", @"category:presets"]];
            for (NSArray *item in categories) [specs addObject:ABMCRow(item[0], item[1], self)];
        } else if ([_category isEqualToString:@"basic"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"基础"]];
            NSArray *actions = @[
        @[@"默认", @"default"], @[@"手电", @"flashlight"], @[@"相机", @"camera"], @[@"静音", @"silent"],
                @[@"截屏", @"screenshot"], @[@"控中", @"controlCenter"], @[@"通知", @"notificationCenter"],
                @[@"聚焦", @"spotlight"], @[@"录屏", @"screenRecord"], @[@"锁屏", @"lock"], @[@"播放", @"mediaPlayPause"],
                @[@"上曲", @"mediaPrevious"], @[@"下曲", @"mediaNext"], @[@"关应", @"closeApps"], @[@"重启", @"respring"],
                @[@"微信扫一扫", @"url:weixin://scanqrcode"], @[@"微信付款码", @"url:weixin://widget/pay"],
                @[@"支付宝扫一扫", @"url:alipay://platformapi/startapp?appId=10000007"], @[@"支付宝付款码", @"url:alipay://platformapi/startapp?appId=20000056"],
                @[@"关闭", @"none"]
            ];
            for (NSArray *item in actions) [specs addObject:ABMCRow(item[0], item[1], self)];
        } else if ([_category isEqualToString:@"apps"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"已安装应用"]];
            Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
            id workspace = workspaceClass ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, NSSelectorFromString(@"defaultWorkspace")) : nil;
            NSArray *apps = workspace && [workspace respondsToSelector:NSSelectorFromString(@"allInstalledApplications")] ? ((id (*)(id, SEL))objc_msgSend)(workspace, NSSelectorFromString(@"allInstalledApplications")) : @[];
            apps = [apps sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                NSString *an = [a respondsToSelector:NSSelectorFromString(@"localizedName")] ? ((id (*)(id, SEL))objc_msgSend)(a, NSSelectorFromString(@"localizedName")) : @"";
                NSString *bn = [b respondsToSelector:NSSelectorFromString(@"localizedName")] ? ((id (*)(id, SEL))objc_msgSend)(b, NSSelectorFromString(@"localizedName")) : @"";
                return [an localizedCaseInsensitiveCompare:bn];
            }];
            for (id app in apps) {
                NSString *bundleID = [app respondsToSelector:NSSelectorFromString(@"bundleIdentifier")] ? ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"bundleIdentifier")) : nil;
                NSString *name = [app respondsToSelector:NSSelectorFromString(@"localizedName")] ? ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"localizedName")) : bundleID;
                if (bundleID.length && name.length) [specs addObject:ABMCRow([NSString stringWithFormat:@"%@\n%@", name, bundleID], [@"app:" stringByAppendingString:bundleID], self)];
            }
        } else if ([_category isEqualToString:@"shortcuts"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"快捷方式"]];
            [specs addObject:ABMCRow(@"输入快捷方式…", @"customShortcut", self)];
        } else if ([_category isEqualToString:@"commands"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"快捷指令"]];
            [specs addObject:ABMCRow(@"运行指令…", @"customCommand", self)];
        } else if ([_category isEqualToString:@"links"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"打开链接"]];
            [specs addObject:ABMCRow(@"新增链接", @"customURL", self)];
        } else if ([_category isEqualToString:@"presets"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:@"预设链接"]];
            [specs addObject:ABMCRow(@"新增链接", @"customURL", self)];
            NSArray *saved = (__bridge NSArray *)CFPreferencesCopyAppValue(CFSTR("customLinks"), (__bridge CFStringRef)PREFS_DOMAIN);
            for (NSDictionary *link in [saved isKindOfClass:[NSArray class]] ? saved : @[]) {
                NSString *title = link[@"title"] ?: link[@"url"];
                NSString *url = link[@"url"];
                if (url.length) [specs addObject:ABMCRow(title, [@"customURL:" stringByAppendingString:url], self)];
            }
        }
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_category.length) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
        CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_prefKey, (__bridge CFStringRef)PREFS_DOMAIN);
        _currentValue = value ? (__bridge_transfer NSString *)value : @"none";
        [self reloadSpecifiers];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    NSString *actionID = [[self specifierAtIndexPath:indexPath] propertyForKey:@"actionID"];
    cell.accessoryType = (actionID.length && ![actionID hasPrefix:@"category:"] && ![actionID isEqualToString:@"__selected__"] && [_currentValue isEqualToString:actionID]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)selectAction:(PSSpecifier *)specifier {
    NSString *actionID = [specifier propertyForKey:@"actionID"];
    if ([actionID isEqualToString:@"__selected__"]) return;
    if ([actionID hasPrefix:@"category:"]) {
        ABMCActionListController *child = [[ABMCActionListController alloc] initWithPreferenceKey:_prefKey category:[actionID substringFromIndex:9]];
        [self.navigationController pushViewController:child animated:YES];
        return;
    }
    if ([actionID isEqualToString:@"customShortcut"] || [actionID isEqualToString:@"customCommand"]) {
        [self promptForValueWithTitle:([actionID isEqualToString:@"customCommand"] ? @"快捷指令" : @"快捷方式") message:@"请输入名称：" prefix:@"shortcut:"];
        return;
    }
    if ([actionID isEqualToString:@"customURL"]) {
        [self promptForURLWithCurrent:nil existingActionID:nil];
        return;
    }
    if ([actionID hasPrefix:@"customURL:"]) {
        [self promptForURLWithCurrent:[actionID substringFromIndex:10] existingActionID:actionID];
        return;
    }
    [self saveAction:actionID];
}

- (void)promptForValueWithTitle:(NSString *)title message:(NSString *)message prefix:(NSString *)prefix {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value.length) [self saveAction:[prefix stringByAppendingString:value]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForURLWithCurrent:(NSString *)current existingActionID:(NSString *)existingActionID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(existingActionID.length ? @"编辑网址" : @"新增网址") message:@"请输入网址或 Scheme：" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = UIKeyboardTypeURL;
        field.text = current;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *url = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSURL *parsed = [NSURL URLWithString:url];
        if (!url.length || !parsed.scheme.length) return;
        [self saveCustomLink:url title:url replacing:existingActionID];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveCustomLink:(NSString *)url title:(NSString *)title replacing:(NSString *)existingActionID {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    NSArray *old = (__bridge NSArray *)CFPreferencesCopyAppValue(CFSTR("customLinks"), (__bridge CFStringRef)PREFS_DOMAIN);
    NSMutableArray *links = [NSMutableArray arrayWithArray:[old isKindOfClass:[NSArray class]] ? old : @[]];
    NSString *oldURL = [existingActionID hasPrefix:@"customURL:"] ? [existingActionID substringFromIndex:10] : nil;
    BOOL replaced = NO;
    for (NSUInteger i = 0; i < links.count; i++) {
        NSDictionary *link = links[i];
        if (oldURL.length && [link[@"url"] isEqualToString:oldURL]) {
            links[i] = @{ @"title": title ?: url, @"url": url };
            replaced = YES;
            break;
        }
    }
    if (!replaced) [links addObject:@{ @"title": title ?: url, @"url": url }];
    CFPreferencesSetAppValue(CFSTR("customLinks"), (__bridge CFPropertyListRef)links, (__bridge CFStringRef)PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    [self saveAction:[@"customURL:" stringByAppendingString:url]];
}

- (void)saveAction:(NSString *)actionID {
    _currentValue = actionID;
    CFPreferencesSetAppValue((__bridge CFStringRef)_prefKey, (__bridge CFPropertyListRef)actionID, (__bridge CFStringRef)PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
    if (_category.length) [self.navigationController popViewControllerAnimated:YES];
    else [self reloadSpecifiers];
}

@end
