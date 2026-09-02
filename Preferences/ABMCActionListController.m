#import "ABMCActionListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sqlite3.h>
#import "../ABMCLogger.h"
#import "ABMCActionEditorController.h"
#import "ABMCLinkEditorController.h"

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static CFPropertyListRef ABMCRead(CFStringRef key) {
    return CFPreferencesCopyValue(key, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void ABMCWrite(CFStringRef key, CFPropertyListRef value) {
    CFPreferencesSetValue(key, value, (__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static NSDictionary *ABMCMetadata(NSString *actionID) {
    CFPropertyListRef raw = ABMCRead(CFSTR("actionMetadata"));
    NSDictionary *all = raw ? (__bridge_transfer NSDictionary *)raw : nil;
    NSDictionary *entry = [all isKindOfClass:[NSDictionary class]] ? all[actionID] : nil;
    return [entry isKindOfClass:[NSDictionary class]] ? entry : @{};
}
static void ABMCSetMetadata(NSString *actionID, NSString *title, NSString *icon, NSString *appName) {
    if (!actionID.length) return;
    CFPropertyListRef raw = ABMCRead(CFSTR("actionMetadata"));
    NSDictionary *old = raw ? (__bridge_transfer NSDictionary *)raw : @{};
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:[old isKindOfClass:[NSDictionary class]] ? old : @{}];
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:ABMCMetadata(actionID)];
    if (title.length) entry[@"title"] = title;
    if (icon.length) entry[@"icon"] = icon;
    if (appName.length) entry[@"appName"] = appName;
    all[actionID] = entry;
    ABMCWrite(CFSTR("actionMetadata"), (__bridge CFPropertyListRef)all);
}
static BOOL ABMCBuiltInURL(NSString *url) {
    if ([url hasPrefix:@"url:"]) url = [url substringFromIndex:4];
    if ([url hasPrefix:@"customURL:"]) url = [url substringFromIndex:10];
    return [@[@"weixin://scanqrcode", @"weixin://widget/pay", @"alipay://platformapi/startapp?appId=10000007", @"alipay://platformapi/startapp?appId=20000056"] containsObject:url];
}
static NSString *ABMCString(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return object && [object respondsToSelector:selector] ? ((id(*)(id,SEL))objc_msgSend)(object, selector) : nil;
}
static NSArray *ABMCShortcutNamesFromDatabase(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @[];
    sqlite3 *database = NULL;
    if (sqlite3_open_v2(path.UTF8String, &database, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { if (database) sqlite3_close(database); return @[]; }
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    sqlite3_stmt *tables = NULL;
    if (sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type='table'", -1, &tables, NULL) == SQLITE_OK) {
        while (sqlite3_step(tables) == SQLITE_ROW) {
            const unsigned char *rawTable = sqlite3_column_text(tables, 0);
            NSString *table = rawTable ? [NSString stringWithUTF8String:(const char *)rawTable] : nil;
            if (!table.length || (![table.lowercaseString containsString:@"workflow"] && ![table.lowercaseString containsString:@"shortcut"])) continue;
            NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(\"%@\")", [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
            sqlite3_stmt *columns = NULL; NSString *nameColumn = nil;
            if (sqlite3_prepare_v2(database, pragma.UTF8String, -1, &columns, NULL) == SQLITE_OK) while (sqlite3_step(columns) == SQLITE_ROW) {
                const unsigned char *rawColumn = sqlite3_column_text(columns, 1);
                NSString *column = rawColumn ? [NSString stringWithUTF8String:(const char *)rawColumn] : nil;
                if ([(@[@"name", @"title", @"workflow_name", @"display_name", @"zname", @"ztitle", @"zworkflowname", @"zdisplayname"]) containsObject:column.lowercaseString]) { nameColumn = column; break; }
            }
            if (columns) sqlite3_finalize(columns);
            if (!nameColumn.length) continue;
            NSString *sql = [NSString stringWithFormat:@"SELECT \"%@\" FROM \"%@\" WHERE \"%@\" IS NOT NULL LIMIT 1000", nameColumn, table, nameColumn];
            sqlite3_stmt *rows = NULL;
            if (sqlite3_prepare_v2(database, sql.UTF8String, -1, &rows, NULL) == SQLITE_OK) while (sqlite3_step(rows) == SQLITE_ROW) {
                const unsigned char *rawName = sqlite3_column_text(rows, 0);
                if (rawName) { NSString *name = [NSString stringWithUTF8String:(const char *)rawName]; if (name.length) [names addObject:name]; }
            }
            if (rows) sqlite3_finalize(rows);
        }
    }
    if (tables) sqlite3_finalize(tables);
    sqlite3_close(database);
    return names.array;
}
static UIImage *ABMCAppIcon(NSString *bundleID) {
    if (!bundleID.length) return nil;
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = workspaceClass && [workspaceClass respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, NSSelectorFromString(@"defaultWorkspace")) : nil;
    NSArray *apps = workspace && [workspace respondsToSelector:NSSelectorFromString(@"allInstalledApplications")] ? ((id(*)(id,SEL))objc_msgSend)(workspace, NSSelectorFromString(@"allInstalledApplications")) : @[];
    for (id app in apps) {
        if (![ABMCString(app, @"bundleIdentifier") isEqualToString:bundleID]) continue;
        id bundleURL = [app respondsToSelector:NSSelectorFromString(@"bundleURL")] ? ((id(*)(id,SEL))objc_msgSend)(app, NSSelectorFromString(@"bundleURL")) : nil;
        NSString *path = [bundleURL respondsToSelector:@selector(path)] ? [bundleURL path] : nil;
        NSDictionary *info = path.length ? [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]] : nil;
        NSArray *iconFiles = info[@"CFBundleIconFiles"];
        NSString *file = [iconFiles isKindOfClass:[NSArray class]] ? iconFiles.lastObject : ([iconFiles isKindOfClass:[NSString class]] ? iconFiles : nil);
        if (!file.length) file = [[info[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"] isKindOfClass:[NSArray class]] ? info[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"] : @[] lastObject];
        UIImage *image = file.length ? [UIImage imageWithContentsOfFile:[path stringByAppendingPathComponent:[file hasSuffix:@".png"] ? file : [file stringByAppendingPathExtension:@"png"]]] : nil;
        if (image) return image;
    }
    return nil;
}
static UIImage *ABMCIconForAction(NSString *actionID, NSString *fallbackBundle) {
    NSString *icon = ABMCMetadata(actionID)[@"icon"] ?: fallbackBundle;
    if (icon.length && [UIImage respondsToSelector:@selector(systemImageNamed:)]) {
        UIImage *symbol = [UIImage systemImageNamed:icon];
        if (symbol) return symbol;
    }
    if (icon.length && [icon containsString:@"."]) {
        UIImage *appIcon = ABMCAppIcon(icon);
        if (appIcon) return appIcon;
    }
    NSDictionary *symbols = @{@"default":@"hand.tap", @"flashlight":@"flashlight.on.fill", @"camera":@"camera.fill", @"silent":@"speaker.slash.fill", @"screenshot":@"camera.viewfinder", @"lock":@"lock.fill", @"respring":@"arrow.clockwise", @"controlCenter":@"switch.2", @"notificationCenter":@"bell.fill", @"spotlight":@"magnifyingglass", @"screenRecord":@"record.circle", @"mediaPlayPause":@"playpause.fill", @"mediaPrevious":@"backward.fill", @"mediaNext":@"forward.fill", @"closeApps":@"rectangle.stack.fill"};
    NSString *symbolName = symbols[actionID];
    return symbolName.length && [UIImage respondsToSelector:@selector(systemImageNamed:)] ? [UIImage systemImageNamed:symbolName] : nil;
}
static NSString *ABMCActionTitle(NSString *actionID) {
    NSDictionary *meta = ABMCMetadata(actionID);
    if ([meta[@"title"] isKindOfClass:[NSString class]] && [meta[@"title"] length]) return meta[@"title"];
    NSDictionary *titles = @{@"default":@"系统默认", @"flashlight":@"手电筒", @"camera":@"相机", @"silent":@"静音模式", @"screenshot":@"屏幕截图", @"lock":@"锁定屏幕", @"respring":@"重启桌面", @"controlCenter":@"控制中心", @"notificationCenter":@"通知中心", @"spotlight":@"聚焦搜索", @"screenRecord":@"屏幕录制", @"mediaPlayPause":@"播放暂停", @"mediaPrevious":@"上一首歌", @"mediaNext":@"下一首歌", @"closeApps":@"关闭应用", @"none":@"关闭动作", @"url:weixin://scanqrcode":@"微信扫一扫", @"url:weixin://widget/pay":@"微信付款码", @"url:alipay://platformapi/startapp?appId=10000007":@"支付宝扫一扫", @"url:alipay://platformapi/startapp?appId=20000056":@"支付宝付款码"};
    if (titles[actionID]) return titles[actionID];
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", meta[@"appName"] ?: [actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"快捷指令：%@", [actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"appshortcut:"]) { NSArray *parts = [[actionID substringFromIndex:12] componentsSeparatedByString:@"|"]; return parts.count > 2 ? parts[2] : @"应用快捷方式"; }
    if ([actionID hasPrefix:@"customURL:"]) {
        NSString *url = [actionID substringFromIndex:10];
        CFPropertyListRef rawLinks = ABMCRead(CFSTR("customLinks"));
        NSArray *links = rawLinks ? (__bridge_transfer NSArray *)rawLinks : @[];
        for (NSDictionary *link in [links isKindOfClass:[NSArray class]] ? links : @[]) if ([link[@"url"] isEqual:url] && [link[@"title"] length]) return link[@"title"];
        return @"自定义链接";
    }
    return actionID.length ? actionID : @"关闭动作";
}
static PSSpecifier *ABMCRow(NSString *title, NSString *actionID, id target, UIImage *icon) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title target:target set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
    [spec setProperty:actionID forKey:@"actionID"];
    if (icon) [spec setProperty:icon forKey:@"iconImage"];
    spec->action = @selector(selectAction:);
    return spec;
}

@interface ABMCActionListController ()
- (void)loadCurrentValueWithFallback:(NSString *)fallback;
- (NSArray *)userApplications;
- (NSArray *)workflowNames;
- (NSArray *)appShortcutGroups;
- (void)deleteActionID:(NSString *)actionID;
- (void)confirmDeleteActionID:(NSString *)actionID;
@end

@implementation ABMCActionListController { NSString *_prefKey; NSString *_currentValue; NSString *_category; BOOL _editingMode; }

- (instancetype)initWithPreferenceKey:(NSString *)preferenceKey category:(NSString *)category {
    self = [super init];
    if (self) { _prefKey = [preferenceKey copy]; _category = [category copy]; [self loadCurrentValueWithFallback:@"none"]; }
    return self;
}
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self = [super init];
    if (self) { _prefKey = [[specifier propertyForKey:@"key"] copy]; _category = [[specifier propertyForKey:@"category"] copy]; [self loadCurrentValueWithFallback:[specifier propertyForKey:@"default"] ?: @"none"]; }
    return self;
}
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    if (!_prefKey.length) { _prefKey = [[specifier propertyForKey:@"key"] copy]; _category = [[specifier propertyForKey:@"category"] copy]; [self loadCurrentValueWithFallback:[specifier propertyForKey:@"default"] ?: @"none"]; }
}
- (void)loadCurrentValueWithFallback:(NSString *)fallback {
    if (!_prefKey.length) { _currentValue = [fallback copy]; return; }
    CFPropertyListRef value = ABMCRead((__bridge CFStringRef)_prefKey);
    _currentValue = value ? (__bridge_transfer NSString *)value : [fallback copy];
}
- (NSString *)gestureTitle {
    return (@{@"singleClickAction":@"单击动作", @"doubleClickAction":@"双击动作", @"longPressAction":@"长按动作"}[_prefKey]) ?: @"动作选择";
}
- (NSString *)categoryTitle {
    return (@{@"basic":@"基础动作", @"apps":@"打开应用", @"shortcuts":@"快捷方式", @"commands":@"快捷指令", @"links":@"打开链接", @"presets":@"预设链接"}[_category]) ?: @"选择动作";
}
- (void)toggleEditing {
    _editingMode = !_editingMode;
    self.navigationItem.rightBarButtonItem.title = _editingMode ? @"完成" : @"编辑动作";
    ABMCLog(@"Editing mode %@ key=%@ category=%@", _editingMode ? @"enabled" : @"disabled", _prefKey ?: @"(nil)", _category ?: @"root");
    _specifiers = nil;
    [self reloadSpecifiers];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _category.length ? [self categoryTitle] : @"选择动作";
    self.navigationItem.prompt = [self gestureTitle];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑动作" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    ABMCLog(@"Selector opened gesture=%@ key=%@ category=%@ current=%@", [self gestureTitle], _prefKey ?: @"(nil)", _category ?: @"root", _currentValue ?: @"(nil)");
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadCurrentValueWithFallback:@"none"];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (NSArray *)userApplications {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = cls && [cls respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id(*)(id,SEL))objc_msgSend)(cls, NSSelectorFromString(@"defaultWorkspace")) : nil;
    NSArray *all = workspace && [workspace respondsToSelector:NSSelectorFromString(@"allInstalledApplications")] ? ((id(*)(id,SEL))objc_msgSend)(workspace, NSSelectorFromString(@"allInstalledApplications")) : @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id app in all) {
        NSString *bundleID = ABMCString(app, @"bundleIdentifier");
        NSString *name = ABMCString(app, @"localizedName");
        id bundleURL = [app respondsToSelector:NSSelectorFromString(@"bundleURL")] ? ((id(*)(id,SEL))objc_msgSend)(app, NSSelectorFromString(@"bundleURL")) : nil;
        NSString *path = [bundleURL respondsToSelector:@selector(path)] ? [bundleURL path] : @"";
        NSString *type = ABMCString(app, @"applicationType");
        BOOL system = [app respondsToSelector:NSSelectorFromString(@"isSystemApplication")] && ((BOOL(*)(id,SEL))objc_msgSend)(app, NSSelectorFromString(@"isSystemApplication"));
        BOOL user = [type isEqualToString:@"User"] || ([app respondsToSelector:NSSelectorFromString(@"isUserApplication")] && ((BOOL(*)(id,SEL))objc_msgSend)(app, NSSelectorFromString(@"isUserApplication")));
        BOOL allowedPath = [path containsString:@"/var/containers/Bundle/Application/"] || [path hasPrefix:@"/var/jb/Applications/"] || [path hasPrefix:@"/Applications/"];
        if (!bundleID.length || !name.length || [seen containsObject:bundleID] || system || (!user && !allowedPath)) continue;
        [seen addObject:bundleID];
        [result addObject:@{@"name":name, @"bundle":bundleID, @"path":path, @"proxy":app}];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}

- (NSArray *)workflowNames {
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    void *handle = dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY);
    if (handle) {
        for (NSString *className in @[@"WFWorkflowStore", @"WFWorkflowCollection", @"WFDatabaseResultSet"]) {
            Class cls = NSClassFromString(className); if (!cls) continue;
            id store = nil;
            for (NSString *factory in @[@"sharedInstance", @"defaultStore", @"defaultWorkflowStore", @"workflowStore"]) { SEL s = NSSelectorFromString(factory); if ([cls respondsToSelector:s]) { store = ((id(*)(id,SEL))objc_msgSend)(cls,s); if (store) break; } }
            if (!store) continue;
            for (NSString *getter in @[@"allWorkflows", @"workflows", @"allWorkflowRecords", @"allWorkflowDescriptors"]) {
                SEL s = NSSelectorFromString(getter); if (![store respondsToSelector:s]) continue;
                id list = ((id(*)(id,SEL))objc_msgSend)(store,s); if (![list isKindOfClass:[NSArray class]]) continue;
                for (id workflow in list) { NSString *name = ABMCString(workflow,@"name") ?: ABMCString(workflow,@"workflowName") ?: ABMCString(workflow,@"localizedName") ?: ABMCString(workflow,@"displayName"); if (name.length) [names addObject:name]; }
            }
        }
    }
    for (NSString *path in @[@"/var/mobile/Library/Shortcuts/Shortcuts.plist", @"/var/mobile/Library/Shortcuts/Shortcuts.json", @"/var/mobile/Library/Shortcuts/ShortcutsStore.plist", @"/private/var/mobile/Library/Shortcuts/Shortcuts.plist", @"/private/var/mobile/Library/Shortcuts/ShortcutsStore.plist"]) {
        id object = [path.pathExtension.lowercaseString isEqualToString:@"json"] ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil] : [NSDictionary dictionaryWithContentsOfFile:path];
        NSArray *items = [object isKindOfClass:[NSArray class]] ? object : ([object isKindOfClass:[NSDictionary class]] ? object[@"workflows"] ?: object[@"shortcuts"] : nil);
        for (id item in items) { NSString *name = [item isKindOfClass:[NSString class]] ? item : (item[@"name"] ?: item[@"title"] ?: item[@"WFWorkflowName"]); if ([name isKindOfClass:[NSString class]] && name.length) [names addObject:name]; }
    }
    for (NSString *path in @[@"/var/mobile/Library/Shortcuts/Shortcuts.sqlite", @"/var/mobile/Library/Shortcuts/Shortcuts.db", @"/var/mobile/Library/Shortcuts/ShortcutsStore.sqlite", @"/var/mobile/Library/Shortcuts/ShortcutsStore.db", @"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite", @"/private/var/mobile/Library/Shortcuts/Shortcuts.db", @"/private/var/mobile/Library/Shortcuts/ShortcutsStore.sqlite", @"/private/var/mobile/Library/Shortcuts/ShortcutsStore.db"]) for (NSString *name in ABMCShortcutNamesFromDatabase(path)) [names addObject:name];
    ABMCLog(@"Loaded shortcut names count=%lu", (unsigned long)names.count);
    return [[names array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray *)appShortcutGroups {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in [self userApplications]) {
        id app = entry[@"proxy"];
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *getter in @[@"staticShortcutItems", @"dynamicShortcutItems", @"shortcutItems"]) {
            SEL selector = NSSelectorFromString(getter);
            if ([app respondsToSelector:selector]) { id value = ((id(*)(id,SEL))objc_msgSend)(app,selector); if ([value isKindOfClass:[NSArray class]]) [items addObjectsFromArray:value]; }
        }
        NSString *path = entry[@"path"];
        NSDictionary *info = path.length ? [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]] : nil;
        NSArray *declared = [info[@"UIApplicationShortcutItems"] isKindOfClass:[NSArray class]] ? info[@"UIApplicationShortcutItems"] : @[];
        [items addObjectsFromArray:declared];
        NSMutableSet *seen = [NSMutableSet set];
        for (id item in items) {
            NSString *type = [item isKindOfClass:[NSDictionary class]] ? item[@"UIApplicationShortcutItemType"] : ABMCString(item,@"type");
            NSString *title = [item isKindOfClass:[NSDictionary class]] ? item[@"UIApplicationShortcutItemTitle"] : (ABMCString(item,@"localizedTitle") ?: ABMCString(item,@"title"));
            if (!type.length || !title.length || [seen containsObject:type]) continue;
            [seen addObject:type];
            NSString *actionID = [NSString stringWithFormat:@"appshortcut:%@|%@|%@", entry[@"bundle"], type, title];
            [groups[entry[@"name"]] ?: (groups[entry[@"name"]] = [NSMutableArray array]) addObject:@{@"title":title, @"action":actionID, @"icon":ABMCIconForAction(actionID, entry[@"bundle"])}];
        }
    }
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in [[groups allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) [result addObject:@{@"name":name, @"items":groups[name]}];
    return result;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];
    if (!_category.length) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"已选择动作"]];
        PSSpecifier *selected = ABMCRow([_currentValue isEqualToString:@"none"] ? @"未选择" : ABMCActionTitle(_currentValue), @"__selected__", self, ABMCIconForAction(_currentValue, nil));
        [selected setProperty:_currentValue forKey:@"realActionID"];
        [specs addObject:selected];
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"动作测试"]];
        [specs addObject:ABMCRow(@"立即测试当前动作", @"__test__", self, nil)];
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"选择动作分组"]];
        NSArray *categories = @[@[@"基础动作", @"category:basic", @"hand.tap.fill"], @[@"打开应用", @"category:apps", @"app.fill"], @[@"快捷方式", @"category:shortcuts", @"square.grid.2x2.fill"], @[@"快捷指令", @"category:commands", @"bolt.fill"], @[@"打开链接", @"category:links", @"safari.fill"], @[@"预设链接", @"category:presets", @"link.circle.fill"]];
        for (NSArray *item in categories) [specs addObject:ABMCRow(item[0], item[1], self, [UIImage systemImageNamed:item[2]])];
    } else if ([_category isEqualToString:@"basic"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"基础动作"]];
        NSArray *actions = @[@[@"系统默认", @"default"], @[@"手电筒", @"flashlight"], @[@"相机", @"camera"], @[@"静音模式", @"silent"], @[@"屏幕截图", @"screenshot"], @[@"控制中心", @"controlCenter"], @[@"通知中心", @"notificationCenter"], @[@"聚焦搜索", @"spotlight"], @[@"屏幕录制", @"screenRecord"], @[@"锁定屏幕", @"lock"], @[@"播放暂停", @"mediaPlayPause"], @[@"上一首歌", @"mediaPrevious"], @[@"下一首歌", @"mediaNext"], @[@"关闭应用", @"closeApps"], @[@"重启桌面", @"respring"], @[@"微信扫一扫", @"url:weixin://scanqrcode"], @[@"微信付款码", @"url:weixin://widget/pay"], @[@"支付宝扫一扫", @"url:alipay://platformapi/startapp?appId=10000007"], @[@"支付宝付款码", @"url:alipay://platformapi/startapp?appId=20000056"], @[@"关闭动作", @"none"]];
        for (NSArray *item in actions) [specs addObject:ABMCRow(item[0], item[1], self, ABMCIconForAction(item[1], nil))];
    } else if ([_category isEqualToString:@"apps"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"用户应用、TrollStore 和越狱应用"]];
        for (NSDictionary *entry in [self userApplications]) {
            NSString *action = [@"app:" stringByAppendingString:entry[@"bundle"]];
            PSSpecifier *row = ABMCRow(entry[@"name"], action, self, ABMCIconForAction(action, entry[@"bundle"]));
            [row setProperty:entry[@"name"] forKey:@"appName"];
            [specs addObject:row];
        }
    } else if ([_category isEqualToString:@"shortcuts"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"快捷方式"]];
        NSArray *groups = [self appShortcutGroups];
        for (NSDictionary *group in groups) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:group[@"name"]]];
            for (NSDictionary *item in group[@"items"]) [specs addObject:ABMCRow(item[@"title"], item[@"action"], self, item[@"icon"] )];
        }
        if (!groups.count) [specs addObject:[PSSpecifier groupSpecifierWithName:@"未读取到应用公开的快捷方式"]];
    } else if ([_category isEqualToString:@"commands"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"快捷指令"]];
        NSArray *names = [self workflowNames];
        for (NSString *name in names) [specs addObject:ABMCRow(name, [@"shortcut:" stringByAppendingString:name], self, [UIImage systemImageNamed:@"shortcuts"] ?: [UIImage systemImageNamed:@"bolt.fill"])];
        [specs addObject:ABMCRow(@"手动输入快捷指令名称", @"customCommand", self, [UIImage systemImageNamed:@"plus"] )];
        if (!names.count) [specs addObject:[PSSpecifier groupSpecifierWithName:@"未读取到快捷指令，可使用上方手动输入"]];
    } else if ([_category isEqualToString:@"links"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"自定义链接"]];
        [specs addObject:ABMCRow(@"新增自定义链接", @"customURL", self, [UIImage systemImageNamed:@"safari.fill"] )];
        CFPropertyListRef raw = ABMCRead(CFSTR("customLinks")); NSArray *saved = raw ? (__bridge_transfer NSArray *)raw : @[];
        for (NSDictionary *link in [saved isKindOfClass:[NSArray class]] ? saved : @[]) {
            NSString *url = link[@"url"]; if (!url.length || ABMCBuiltInURL(url)) continue;
            NSString *action = [@"customURL:" stringByAppendingString:url];
            [specs addObject:ABMCRow(link[@"title"] ?: url, action, self, ABMCIconForAction(action, link[@"icon"]))];
        }
    } else if ([_category isEqualToString:@"presets"]) {
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"预设链接"]];
        NSArray *items = @[@[@"网页搜索", @"customURL:https://www.baidu.com/s?wd=$$$"], @[@"地图搜索", @"customURL:maps://?q=$$$"], @[@"剪贴板搜索", @"customURL:https://www.google.com/search?q=$$$"]];
        for (NSArray *item in items) [specs addObject:ABMCRow(item[0], item[1], self, [UIImage systemImageNamed:@"safari.fill"] )];
    }
    _specifiers = specs;
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:path];
    PSSpecifier *specifier = [self specifierAtIndexPath:path];
    NSString *actionID = [specifier propertyForKey:@"actionID"];
    UIImage *image = [specifier propertyForKey:@"iconImage"];
    if (image) cell.imageView.image = image;
    if ([actionID isEqualToString:@"__selected__"]) actionID = _currentValue;
    if (_editingMode && actionID.length && ![actionID hasPrefix:@"category:"] && ![actionID isEqualToString:@"__test__"]) cell.accessoryType = UITableViewCellAccessoryDetailButton;
    else if (actionID.length && [_currentValue isEqualToString:actionID]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
    else if ([actionID hasPrefix:@"category:"] || [actionID isEqualToString:@"customURL"] || [actionID isEqualToString:@"customCommand"]) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    else cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)selectAction:(PSSpecifier *)specifier {
    NSString *actionID = [specifier propertyForKey:@"actionID"];
    if (!actionID.length) return;
    ABMCLog(@"Action row tapped gesture=%@ category=%@ id=%@ editing=%@", [self gestureTitle], _category ?: @"root", actionID, _editingMode ? @"yes" : @"no");
    if ([actionID isEqualToString:@"__selected__"]) {
        NSString *selectedID = _currentValue;
        if (_editingMode && selectedID.length && ![selectedID isEqualToString:@"none"]) [self confirmDeleteActionID:selectedID];
        else if (selectedID.length && ![selectedID isEqualToString:@"none"]) [self editActionID:selectedID];
        return;
    }
    if ([actionID isEqualToString:@"__test__"]) {
        if (_currentValue.length && ![_currentValue isEqualToString:@"none"]) {
            ABMCWrite(CFSTR("testAction"), (__bridge CFPropertyListRef)_currentValue);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
        }
        return;
    }
    if ([actionID hasPrefix:@"category:"]) {
        ABMCActionListController *child = [[ABMCActionListController alloc] initWithPreferenceKey:_prefKey category:[actionID substringFromIndex:9]];
        [self.navigationController pushViewController:child animated:YES]; return;
    }
    if (_editingMode) { [self confirmDeleteActionID:actionID]; return; }
    if ([actionID isEqualToString:@"customCommand"]) { [self promptForValueWithTitle:@"快捷指令" prefix:@"shortcut:"]; return; }
    if ([actionID isEqualToString:@"customURL"]) { [self.navigationController pushViewController:[[ABMCLinkEditorController alloc] initWithPreferenceKey:_prefKey existingURL:nil] animated:YES]; return; }
    NSString *appName = [specifier propertyForKey:@"appName"];
    [self saveAction:actionID title:nil icon:nil appName:appName];
}

- (void)editActionID:(NSString *)actionID {
    if ([actionID hasPrefix:@"customURL:"]) {
        [self.navigationController pushViewController:[[ABMCLinkEditorController alloc] initWithPreferenceKey:_prefKey existingURL:[actionID substringFromIndex:10]] animated:YES];
    } else {
        [self.navigationController pushViewController:[[ABMCActionEditorController alloc] initWithPreferenceKey:_prefKey actionID:actionID] animated:YES];
    }
}

- (void)confirmDeleteActionID:(NSString *)actionID {
    if (!actionID.length || [actionID hasPrefix:@"category:"] || [actionID isEqualToString:@"none"]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除动作" message:[NSString stringWithFormat:@"确定删除“%@”吗？", ABMCActionTitle(actionID)] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *unused) { [self deleteActionID:actionID]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteActionID:(NSString *)actionID {
    if (!actionID.length || [actionID hasPrefix:@"category:"] || [actionID isEqualToString:@"none"]) return;
    BOOL selected = [_currentValue isEqualToString:actionID];
    if (selected) {
        _currentValue = @"none";
        ABMCWrite((__bridge CFStringRef)_prefKey, (__bridge CFPropertyListRef)@"none");
    }
    CFPropertyListRef raw = ABMCRead(CFSTR("actionMetadata"));
    NSDictionary *oldMetadata = raw ? (__bridge_transfer NSDictionary *)raw : @{};
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:[oldMetadata isKindOfClass:[NSDictionary class]] ? oldMetadata : @{}];
    [metadata removeObjectForKey:actionID];
    ABMCWrite(CFSTR("actionMetadata"), (__bridge CFPropertyListRef)metadata);
    if ([actionID hasPrefix:@"customURL:"]) {
        NSString *url = [actionID substringFromIndex:10];
        CFPropertyListRef linkRaw = ABMCRead(CFSTR("customLinks"));
        NSArray *saved = linkRaw ? (__bridge_transfer NSArray *)linkRaw : @[];
        NSMutableArray *links = [NSMutableArray array];
        for (NSDictionary *link in [saved isKindOfClass:[NSArray class]] ? saved : @[]) if (![link[@"url"] isEqual:url]) [links addObject:link];
        ABMCWrite(CFSTR("customLinks"), (__bridge CFPropertyListRef)links);
    }
    ABMCLog(@"Action deleted gesture=%@ category=%@ id=%@ selected=%@", [self gestureTitle], _category ?: @"root", actionID, selected ? @"yes" : @"no");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *actionID = [specifier propertyForKey:@"actionID"];
    if (actionID.length && ![actionID hasPrefix:@"category:"] && ![actionID isEqualToString:@"__test__"] && ![actionID isEqualToString:@"customURL"] && ![actionID isEqualToString:@"customCommand"]) [self editActionID:[actionID isEqualToString:@"__selected__"] ? _currentValue : actionID];
}

- (void)promptForValueWithTitle:(NSString *)title prefix:(NSString *)prefix {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"请输入快捷指令名称" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (value.length) [self saveAction:[prefix stringByAppendingString:value] title:nil icon:nil appName:nil]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveAction:(NSString *)actionID title:(NSString *)title icon:(NSString *)icon appName:(NSString *)appName {
    if (!_prefKey.length || !actionID.length) { ABMCLog(@"Action save rejected key=%@ id=%@", _prefKey ?: @"(nil)", actionID ?: @"(nil)"); return; }
    if (title.length || icon.length || appName.length) ABMCSetMetadata(actionID, title, icon, appName);
    _currentValue = [actionID copy];
    ABMCWrite((__bridge CFStringRef)_prefKey, (__bridge CFPropertyListRef)actionID);
    CFPropertyListRef confirmed = ABMCRead((__bridge CFStringRef)_prefKey);
    ABMCLog(@"Action saved gesture=%@ key=%@ id=%@ confirmed=%@", [self gestureTitle], _prefKey, actionID, confirmed ? @"yes" : @"no");
    if (confirmed) CFRelease(confirmed);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
    if (_category.length) [self.navigationController popViewControllerAnimated:YES]; else { _specifiers = nil; [self reloadSpecifiers]; }
}
@end
