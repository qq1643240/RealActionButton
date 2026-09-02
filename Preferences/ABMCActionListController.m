#import "ABMCActionListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../ABMCLogger.h"

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static CFPropertyListRef ABMCRead(CFStringRef key) { return CFPreferencesCopyValue(key, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); }
static void ABMCWrite(CFStringRef key, CFPropertyListRef value) { CFPreferencesSetValue(key, value, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); CFPreferencesSynchronize((__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); }
static BOOL ABMCBuiltInURL(NSString *url) {
    if ([url hasPrefix:@"url:"]) url = [url substringFromIndex:4];
    if ([url hasPrefix:@"customURL:"]) url = [url substringFromIndex:10];
    return [@[@"weixin://scanqrcode", @"weixin://widget/pay", @"alipay://platformapi/startapp?appId=10000007", @"alipay://platformapi/startapp?appId=20000056"] containsObject:url];
}
static NSString *ABMCString(id object, NSString *selectorName) { SEL s=NSSelectorFromString(selectorName); return object && [object respondsToSelector:s] ? ((id(*)(id,SEL))objc_msgSend)(object,s) : nil; }

static NSString *ABMCActionTitle(NSString *actionID) {
    if ([actionID isEqualToString:@"url:weixin://scanqrcode"]) return @"微信扫一扫";
    if ([actionID isEqualToString:@"url:weixin://widget/pay"]) return @"微信付款码";
    if ([actionID isEqualToString:@"url:alipay://platformapi/startapp?appId=10000007"]) return @"支付宝扫一扫";
    if ([actionID isEqualToString:@"url:alipay://platformapi/startapp?appId=20000056"]) return @"支付宝付款码";
    NSDictionary *titles=@{@"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音模式",@"screenshot":@"屏幕截图",@"lock":@"锁定屏幕",@"respring":@"重启桌面",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"spotlight":@"聚焦搜索",@"screenRecord":@"屏幕录制",@"mediaPlayPause":@"播放暂停",@"mediaPrevious":@"上一首歌",@"mediaNext":@"下一首歌",@"closeApps":@"关闭应用",@"none":@"关闭动作"};
    if (titles[actionID]) return titles[actionID];
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@",[actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"快捷指令：%@",[actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"appshortcut:"]) { NSArray *p=[[actionID substringFromIndex:12] componentsSeparatedByString:@"|"]; return p.count>2 ? [NSString stringWithFormat:@"应用快捷方式：%@",p[2]] : @"应用快捷方式"; }
    if ([actionID hasPrefix:@"customURL:"]) return [NSString stringWithFormat:@"链接：%@",[actionID substringFromIndex:10]];
    return actionID.length ? actionID : @"关闭动作";
}

static PSSpecifier *ABMCRow(NSString *title, NSString *actionID, id target) {
    PSSpecifier *spec=[PSSpecifier preferenceSpecifierNamed:title target:target set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
    [spec setProperty:actionID forKey:@"actionID"];
    spec->action = @selector(selectAction:);
    return spec;
}

@interface ABMCActionListController ()
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
- (void)loadCurrentValueWithFallback:(NSString *)fallback;
- (NSArray *)userApplications;
- (NSArray *)workflowNames;
- (NSArray *)appShortcutRows;
- (void)promptForValueWithTitle:(NSString *)title prefix:(NSString *)prefix;
- (void)promptForURLWithCurrent:(NSString *)current existingActionID:(NSString *)existingActionID;
- (void)saveCustomLink:(NSString *)url title:(NSString *)title replacing:(NSString *)existingActionID;
- (void)saveAction:(NSString *)actionID;
@end

@implementation ABMCActionListController { NSString *_prefKey; NSString *_currentValue; NSString *_category; }

- (instancetype)initWithPreferenceKey:(NSString *)preferenceKey category:(NSString *)category {
    self=[super init];
    if (self) { _prefKey=[preferenceKey copy]; _category=[category copy]; [self loadCurrentValueWithFallback:@"none"]; }
    return self;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self = [super init];
    if (self) {
        _prefKey = [[specifier propertyForKey:@"key"] copy];
        _category = [[specifier propertyForKey:@"category"] copy];
        [self loadCurrentValueWithFallback:[specifier propertyForKey:@"default"] ?: @"none"];
    }
    return self;
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    if (!_prefKey.length) { _prefKey=[[specifier propertyForKey:@"key"] copy]; _category=[[specifier propertyForKey:@"category"] copy]; [self loadCurrentValueWithFallback:[specifier propertyForKey:@"default"] ?: @"none"]; }
}

- (void)loadCurrentValueWithFallback:(NSString *)fallback {
    if (!_prefKey.length) { _currentValue=[fallback copy]; return; }
    CFPropertyListRef value=ABMCRead((__bridge CFStringRef)_prefKey);
    _currentValue=value ? (__bridge_transfer NSString *)value : [fallback copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!_prefKey.length) { PSSpecifier *parent=[self specifier]; _prefKey=[[parent propertyForKey:@"key"] copy]; _category=[[parent propertyForKey:@"category"] copy]; [self loadCurrentValueWithFallback:[parent propertyForKey:@"default"] ?: @"none"]; }
    self.title=_category.length ? [self categoryTitle] : @"选择动作";
    ABMCLog(@"Preferences selector opened key=%@ category=%@ current=%@", _prefKey ?: @"(nil)", _category ?: @"root", _currentValue ?: @"(nil)");
    if ([_category isEqualToString:@"links"]) [self.table addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLinkLongPress:)]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self loadCurrentValueWithFallback:@"none"]; _specifiers=nil; [self reloadSpecifiers]; }
- (NSString *)categoryTitle { return (@{@"basic":@"基础动作",@"apps":@"应用列表",@"shortcuts":@"应用快捷方式",@"commands":@"快捷指令",@"links":@"自定义链接",@"presets":@"系统预设"}[_category]) ?: @"选择动作"; }

- (NSArray *)userApplications {
    Class cls=NSClassFromString(@"LSApplicationWorkspace"); id ws=cls && [cls respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"defaultWorkspace")) : nil;
    NSArray *all=ws && [ws respondsToSelector:NSSelectorFromString(@"allInstalledApplications")] ? ((id(*)(id,SEL))objc_msgSend)(ws,NSSelectorFromString(@"allInstalledApplications")) : @[];
    NSMutableArray *result=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for (id app in all) {
        NSString *bid=ABMCString(app,@"bundleIdentifier"); NSString *name=ABMCString(app,@"localizedName"); NSString *type=ABMCString(app,@"applicationType");
        id bundleURL=app && [app respondsToSelector:NSSelectorFromString(@"bundleURL")] ? ((id(*)(id,SEL))objc_msgSend)(app,NSSelectorFromString(@"bundleURL")) : nil;
        NSString *path=[bundleURL respondsToSelector:@selector(path)] ? [bundleURL path] : @"";
        BOOL user = [type isEqualToString:@"User"] || ([app respondsToSelector:NSSelectorFromString(@"isUserApplication")] && ((BOOL(*)(id,SEL))objc_msgSend)(app, NSSelectorFromString(@"isUserApplication")));
        BOOL jailbreak=[path hasPrefix:@"/var/jb/"];
        if (!bid.length || !name.length || [seen containsObject:bid] || (!user && !jailbreak)) continue;
        [seen addObject:bid]; [result addObject:@{@"name":name,@"bundle":bid,@"proxy":app}];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}

- (NSArray *)workflowNames {
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSet];
    dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY);
    for (NSString *className in @[@"WFWorkflowStore",@"WFWorkflowCollection",@"WFDatabaseResultSet"]) {
        Class cls=NSClassFromString(className); if (!cls) continue;
        id store=nil;
        for (NSString *factory in @[@"sharedInstance",@"defaultStore",@"defaultWorkflowStore",@"workflowStore"]) { SEL s=NSSelectorFromString(factory); if ([cls respondsToSelector:s]) { store=((id(*)(id,SEL))objc_msgSend)(cls,s); if (store) break; } }
        if (!store) continue;
        for (NSString *getter in @[@"allWorkflows",@"workflows",@"allWorkflowRecords"]) { SEL s=NSSelectorFromString(getter); if (![store respondsToSelector:s]) continue; id list=((id(*)(id,SEL))objc_msgSend)(store,s); if (![list isKindOfClass:[NSArray class]]) continue; for (id workflow in list) { NSString *name=ABMCString(workflow,@"name") ?: ABMCString(workflow,@"workflowName") ?: ABMCString(workflow,@"localizedName"); if (name.length) [names addObject:name]; } }
    }
    return [[names array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray *)appShortcutRows {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *entry in [self userApplications]) {
        id app = entry[@"proxy"];
        NSString *bundleID = entry[@"bundle"];
        NSString *appName = entry[@"name"];
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *getter in @[@"staticShortcutItems", @"dynamicShortcutItems", @"shortcutItems"]) {
            SEL selector = NSSelectorFromString(getter);
            if ([app respondsToSelector:selector]) {
                id value = ((id(*)(id,SEL))objc_msgSend)(app, selector);
                if ([value isKindOfClass:[NSArray class]]) [items addObjectsFromArray:value];
            }
        }
        id bundleURL = [app respondsToSelector:NSSelectorFromString(@"bundleURL")] ? ((id(*)(id,SEL))objc_msgSend)(app, NSSelectorFromString(@"bundleURL")) : nil;
        NSString *bundlePath = [bundleURL respondsToSelector:@selector(path)] ? [bundleURL path] : nil;
        NSDictionary *info = bundlePath.length ? [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]] : nil;
        NSArray *staticItems = [info[@"UIApplicationShortcutItems"] isKindOfClass:[NSArray class]] ? info[@"UIApplicationShortcutItems"] : @[];
        [items addObjectsFromArray:staticItems];
        for (id item in items) {
            NSString *type = [item isKindOfClass:[NSDictionary class]] ? item[@"UIApplicationShortcutItemType"] : (ABMCString(item,@"type") ?: ABMCString(item,@"shortcutType"));
            NSString *title = [item isKindOfClass:[NSDictionary class]] ? item[@"UIApplicationShortcutItemTitle"] : (ABMCString(item,@"localizedTitle") ?: ABMCString(item,@"title"));
            if (!title.length) title = type;
            if (!type.length || !title.length) continue;
            NSString *key = [NSString stringWithFormat:@"%@|%@", bundleID, type];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [rows addObject:@{@"title":[NSString stringWithFormat:@"%@ · %@", appName, title], @"id":[NSString stringWithFormat:@"appshortcut:%@|%@|%@", bundleID, type, title]}];
        }
    }
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"title"] localizedCaseInsensitiveCompare:b[@"title"]]; }];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs=[NSMutableArray array];
    if (!_category.length) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"已选择动作"]];
        [specs addObject:ABMCRow([_currentValue isEqualToString:@"none"] ? @"未选择" : ABMCActionTitle(_currentValue),@"__selected__",self)];
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"动作测试"]];
        [specs addObject:ABMCRow(@"立即测试当前动作",@"__test__",self)];
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"选择动作分组"]];
        for (NSArray *item in @[@[@"基础动作",@"category:basic"],@[@"应用列表",@"category:apps"],@[@"应用快捷方式",@"category:shortcuts"],@[@"快捷指令",@"category:commands"],@[@"自定义链接",@"category:links"],@[@"系统预设",@"category:presets"]]) [specs addObject:ABMCRow(item[0],item[1],self)];
    } else if ([_category isEqualToString:@"basic"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"基础动作"]];
        NSArray *actions=@[@[@"系统默认",@"default"],@[@"手电筒",@"flashlight"],@[@"相机",@"camera"],@[@"静音模式",@"silent"],@[@"屏幕截图",@"screenshot"],@[@"控制中心",@"controlCenter"],@[@"通知中心",@"notificationCenter"],@[@"聚焦搜索",@"spotlight"],@[@"屏幕录制",@"screenRecord"],@[@"锁定屏幕",@"lock"],@[@"播放暂停",@"mediaPlayPause"],@[@"上一首歌",@"mediaPrevious"],@[@"下一首歌",@"mediaNext"],@[@"关闭应用",@"closeApps"],@[@"重启桌面",@"respring"],@[@"微信扫一扫",@"url:weixin://scanqrcode"],@[@"微信付款码",@"url:weixin://widget/pay"],@[@"支付宝扫一扫",@"url:alipay://platformapi/startapp?appId=10000007"],@[@"支付宝付款码",@"url:alipay://platformapi/startapp?appId=20000056"],@[@"关闭动作",@"none"]];
        for (NSArray *item in actions) [specs addObject:ABMCRow(item[0],item[1],self)];
    } else if ([_category isEqualToString:@"apps"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"用户、TrollStore 与越狱应用"]];
        for (NSDictionary *entry in [self userApplications]) [specs addObject:ABMCRow([NSString stringWithFormat:@"%@\n%@",entry[@"name"],entry[@"bundle"]],[@"app:" stringByAppendingString:entry[@"bundle"]],self)];
    } else if ([_category isEqualToString:@"shortcuts"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"应用快捷方式"]];
        NSArray *rows=[self appShortcutRows];
        if (!rows.count) [specs addObject:[PSSpecifier groupSpecifierWithName:@"没有可读取的应用快捷方式；仅显示应用自身公开的主屏幕快捷方式。"]];
        for (NSDictionary *row in rows) [specs addObject:ABMCRow(row[@"title"],row[@"id"],self)];
    } else if ([_category isEqualToString:@"commands"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"快捷指令"]];
        NSArray *names=[self workflowNames];
        for (NSString *name in names) [specs addObject:ABMCRow(name,[@"shortcut:" stringByAppendingString:name],self)];
        [specs addObject:ABMCRow(@"手动输入快捷指令名称",@"customCommand",self)];
    } else if ([_category isEqualToString:@"links"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"自定义链接"]]; [specs addObject:ABMCRow(@"新增自定义链接",@"customURL",self)];
        CFPropertyListRef raw=ABMCRead(CFSTR("customLinks")); NSArray *saved=raw ? (__bridge_transfer NSArray *)raw : @[];
        for (NSDictionary *link in [saved isKindOfClass:[NSArray class]] ? saved : @[]) { NSString *url=link[@"url"]; if (!url.length || ABMCBuiltInURL(url)) continue; [specs addObject:ABMCRow(link[@"title"] ?: url,[@"customURL:" stringByAppendingString:url],self)]; }
    } else if ([_category isEqualToString:@"presets"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"系统预设链接"]];
        for (NSArray *item in @[@[@"搜索剪贴板",@"customURL:https://www.google.com/search?q=$$$"],@[@"地图搜索",@"customURL:maps://?q=$$$"],@[@"网页搜索",@"customURL:https://www.baidu.com/s?wd=$$$"]]) [specs addObject:ABMCRow(item[0],item[1],self)];
    }
    _specifiers=specs; return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:path]; NSString *actionID=[[self specifierAtIndexPath:path] propertyForKey:@"actionID"]; cell.accessoryType=actionID.length && ![actionID hasPrefix:@"category:"] && ![actionID isEqualToString:@"__selected__"] && [_currentValue isEqualToString:actionID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator; return cell; }

- (void)selectAction:(PSSpecifier *)specifier {
    NSString *actionID=[specifier propertyForKey:@"actionID"];
    ABMCLog(@"Preferences row selected key=%@ category=%@ action=%@", _prefKey ?: @"(nil)", _category ?: @"root", actionID ?: @"(nil)");
    if (!actionID.length || [actionID isEqualToString:@"__selected__"]) return;
    if ([actionID isEqualToString:@"__test__"]) {
        if (!_currentValue.length || [_currentValue isEqualToString:@"none"]) {
            ABMCLog(@"Preferences test skipped: no enabled action");
            return;
        }
        ABMCWrite(CFSTR("testAction"), (__bridge CFPropertyListRef)_currentValue);
        ABMCLog(@"Preferences requested immediate test action=%@", _currentValue);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
        return;
    }
    if ([actionID hasPrefix:@"category:"]) {
        ABMCActionListController *child=[[ABMCActionListController alloc] initWithPreferenceKey:_prefKey category:[actionID substringFromIndex:9]];
        [self.navigationController pushViewController:child animated:YES];
        return;
    }
    if ([actionID isEqualToString:@"customCommand"]) { [self promptForValueWithTitle:@"快捷指令" prefix:@"shortcut:"]; return; }
    if ([actionID isEqualToString:@"customURL"]) { [self promptForURLWithCurrent:nil existingActionID:nil]; return; }
    [self saveAction:actionID];
}

- (void)handleLinkLongPress:(UILongPressGestureRecognizer *)gesture { if (gesture.state!=UIGestureRecognizerStateBegan) return; NSIndexPath *path=[self.table indexPathForRowAtPoint:[gesture locationInView:self.table]]; NSString *actionID=path ? [[self specifierAtIndexPath:path] propertyForKey:@"actionID"] : nil; if ([actionID hasPrefix:@"customURL:"]) [self promptForURLWithCurrent:[actionID substringFromIndex:10] existingActionID:actionID]; }
- (void)promptForValueWithTitle:(NSString *)title prefix:(NSString *)prefix { UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:@"请输入名称" preferredStyle:UIAlertControllerStyleAlert]; [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){NSString *v=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(v.length)[self saveAction:[prefix stringByAppendingString:v]];}]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)promptForURLWithCurrent:(NSString *)current existingActionID:(NSString *)oldID { UIAlertController *a=[UIAlertController alertControllerWithTitle:oldID.length ? @"编辑自定义链接" : @"新增自定义链接" message:@"支持 @@@ 输入、$$$ 剪贴板" preferredStyle:UIAlertControllerStyleAlert]; [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;f.keyboardType=UIKeyboardTypeURL;f.text=current;}]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){NSString *u=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(u.length && [NSURL URLWithString:u].scheme.length && !ABMCBuiltInURL(u))[self saveCustomLink:u title:u replacing:oldID];}]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)saveCustomLink:(NSString *)url title:(NSString *)title replacing:(NSString *)oldID {
    CFPropertyListRef raw = ABMCRead(CFSTR("customLinks"));
    NSArray *saved = raw ? (__bridge_transfer NSArray *)raw : @[];
    NSMutableArray *links = [NSMutableArray arrayWithArray:[saved isKindOfClass:[NSArray class]] ? saved : @[]];
    NSString *oldURL = [oldID hasPrefix:@"customURL:"] ? [oldID substringFromIndex:10] : nil;
    BOOL replaced = NO;
    for (NSUInteger i = 0; i < links.count; i++) {
        NSDictionary *link = links[i];
        if (oldURL.length && [link[@"url"] isEqual:oldURL]) {
            links[i] = @{ @"title": title ?: url, @"url": url };
            replaced = YES;
            break;
        }
    }
    if (!replaced) [links addObject:@{ @"title": title ?: url, @"url": url }];
    ABMCWrite(CFSTR("customLinks"), (__bridge CFPropertyListRef)links);
    [self saveAction:[@"customURL:" stringByAppendingString:url]];
}
- (void)saveAction:(NSString *)actionID {
    if (!_prefKey.length || !actionID.length) {
        ABMCLog(@"Preferences save rejected key=%@ action=%@", _prefKey ?: @"(nil)", actionID ?: @"(nil)");
        return;
    }
    _currentValue=[actionID copy];
    ABMCWrite((__bridge CFStringRef)_prefKey,(__bridge CFPropertyListRef)actionID);
    CFPropertyListRef saved = ABMCRead((__bridge CFStringRef)_prefKey);
    NSString *confirmed = saved ? (__bridge_transfer NSString *)saved : nil;
    ABMCLog(@"Preferences saved key=%@ action=%@ confirmed=%@", _prefKey, actionID, confirmed ?: @"(nil)");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)PREFS_NOTIFICATION,NULL,NULL,YES);
    if(_category.length)[self.navigationController popViewControllerAnimated:YES];
    else{_specifiers=nil;[self reloadSpecifiers];}
}
@end
