#import "ABMCActionExecutor.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <SpringBoardServices/SpringBoardServices.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../ABMCLogger.h"

typedef void (*ABMCSBSLaunchFunction)(CFStringRef, BOOL);

#define PREFS_DOMAIN CFSTR("com.huynguyen.actionbuttonmulticlick")

static CFPropertyListRef ABMCReadPreference(CFStringRef key) {
    return CFPreferencesCopyValue(key, PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static void ABMCLoadShortcutsRuntime(void) {
    for (NSString *path in @[@"/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", @"/System/Library/PrivateFrameworks/WorkflowUI.framework/WorkflowUI", @"/Applications/Shortcuts.app/Shortcuts"]) dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultSelector] ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
        SEL proxySelector = NSSelectorFromString(@"applicationForBundleIdentifier:");
        id shortcutProxy = workspace && [workspace respondsToSelector:proxySelector] ? ((id(*)(id,SEL,id))objc_msgSend)(workspace, proxySelector, @"com.apple.shortcuts") : nil;
        SEL bundleURLSelector = NSSelectorFromString(@"bundleURL");
        id bundleURL = shortcutProxy && [shortcutProxy respondsToSelector:bundleURLSelector] ? ((id(*)(id,SEL))objc_msgSend)(shortcutProxy, bundleURLSelector) : nil;
        NSString *bundlePath = [bundleURL respondsToSelector:@selector(path)] ? [bundleURL path] : nil;
        for (NSString *relative in @[@"Shortcuts", @"Frameworks/WorkflowKit.framework/WorkflowKit", @"Frameworks/WorkflowUI.framework/WorkflowUI"]) {
            NSString *path = bundlePath.length ? [bundlePath stringByAppendingPathComponent:relative] : nil;
            if (path.length) dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
        }
    } @catch (__unused NSException *exception) {}
}

BOOL ABMCPerformingDefaultAction = NO;

@interface ABMCActionExecutor ()
- (void)openURLString:(NSString *)urlString;
- (void)executeAppShortcut:(NSString *)payload;
- (void)runShortcutWorkflowIdentifier:(NSString *)payload;
- (BOOL)invokeCandidates:(NSArray<NSString *> *)selectors classes:(NSArray<NSString *> *)classes argument:(id)argument;
- (void)performNamedSystemAction:(NSString *)action;
- (void)invokeSystemAction:(NSString *)selectorName;
- (void)invokeMediaSelector:(NSString *)selectorName;
- (void)invokeMediaSelector:(NSString *)selectorName argument:(id)argument;
@end

@implementation ABMCActionExecutor {
    NSString *_singleAction;
    NSString *_doubleAction;
    NSString *_longPressAction;
}

+ (instancetype)sharedExecutor {
    static ABMCActionExecutor *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ABMCActionExecutor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self reloadPreferences];
    }
    return self;
}

- (void)reloadPreferences {
    CFStringRef single = (CFStringRef)ABMCReadPreference(CFSTR("singleClickAction"));
    CFStringRef dbl = (CFStringRef)ABMCReadPreference(CFSTR("doubleClickAction"));
    CFStringRef longPress = (CFStringRef)ABMCReadPreference(CFSTR("longPressAction"));

    _singleAction = single ? (__bridge_transfer NSString *)single : @"default";
    _doubleAction = dbl ? (__bridge_transfer NSString *)dbl : @"none";
    _longPressAction = longPress ? (__bridge_transfer NSString *)longPress : @"default";
    ABMCLog(@"SpringBoard preferences loaded single=%@ double=%@ long=%@", _singleAction, _doubleAction, _longPressAction);
}

- (NSString *)actionForClickCount:(NSInteger)count {
    switch (count) {
        case 1: return _singleAction;
        case 2: return _doubleAction;
        default: return @"none";
    }
}

- (void)executeActionForClickType:(NSInteger)clickType {
    NSString *action = [self actionForClickCount:clickType];
    ABMCLog(@"Click resolved count=%ld action=%@", (long)clickType, action ?: @"(nil)");
    [self executeAction:action];
}

- (BOOL)usesDefaultLongPressAction {
    return [_longPressAction isEqualToString:@"default"];
}

- (void)executeLongPressAction {
    ABMCLog(@"Long press resolved action=%@", _longPressAction ?: @"(nil)");
    [self executeAction:_longPressAction];
}

- (void)executeAction:(NSString *)actionID {
    ABMCLog(@"Action execution requested id=%@", actionID ?: @"(nil)");
    if (!actionID || [actionID isEqualToString:@"none"]) {
        ABMCLog(@"Action execution skipped: disabled or empty");
        return;
    }

    if ([actionID isEqualToString:@"default"]) {
        [self performDefaultAction];
    } else if ([actionID isEqualToString:@"flashlight"]) {
        [self toggleFlashlight];
    } else if ([actionID isEqualToString:@"camera"]) {
        [self openApp:@"com.apple.camera"];
    } else if ([actionID isEqualToString:@"silent"]) {
        [self toggleSilentMode];
    } else if ([actionID isEqualToString:@"screenshot"]) {
        [self takeScreenshot];
    } else if ([actionID isEqualToString:@"lock"]) {
        [self lockDevice];
    } else if ([actionID isEqualToString:@"respring"]) {
        [self respring];
    } else if ([actionID isEqualToString:@"controlCenter"]) {
        [self performNamedSystemAction:@"controlCenter"];
    } else if ([actionID isEqualToString:@"notificationCenter"]) {
        [self performNamedSystemAction:@"notificationCenter"];
    } else if ([actionID isEqualToString:@"spotlight"]) {
        [self performNamedSystemAction:@"spotlight"];
    } else if ([actionID isEqualToString:@"screenRecord"]) {
        [self performNamedSystemAction:@"screenRecord"];
    } else if ([actionID isEqualToString:@"mediaPlayPause"]) {
        [self performNamedSystemAction:@"mediaPlayPause"];
    } else if ([actionID isEqualToString:@"mediaPrevious"]) {
        [self performNamedSystemAction:@"mediaPrevious"];
    } else if ([actionID isEqualToString:@"mediaNext"]) {
        [self performNamedSystemAction:@"mediaNext"];
    } else if ([actionID isEqualToString:@"closeApps"]) {
        [self performNamedSystemAction:@"closeApps"];
    } else if ([actionID hasPrefix:@"app:"]) {
        [self openApp:[actionID substringFromIndex:4]];
    } else if ([actionID hasPrefix:@"appshortcut:"]) {
        [self executeAppShortcut:[actionID substringFromIndex:12]];
    } else if ([actionID hasPrefix:@"shortcutuuid:"]) {
        [self runShortcutWorkflowIdentifier:[actionID substringFromIndex:13]];
    } else if ([actionID hasPrefix:@"shortcut:"]) {
        [self runShortcut:[actionID substringFromIndex:9]];
    } else if ([actionID hasPrefix:@"customURL:"]) {
        [self openURLString:[actionID substringFromIndex:10]];
    } else if ([actionID hasPrefix:@"url:"]) {
        [self openURLString:[actionID substringFromIndex:4]];
    }
}

#pragma mark - Default Action (replay through original hooks)

- (void)performDefaultAction {
    id button = self.buttonInstance;
    if (!button) return;

    ABMCPerformingDefaultAction = YES;
    @try {
        // Replay full cycle: buttonDown → longPress → buttonUp
        // buttonDown sets up internal state (assertions, preview)
        // longPress performs the configured action
        // buttonUp cleans up state (invalidates assertions, dismisses Dynamic Island)
        SEL downSel = NSSelectorFromString(@"performActionsForButtonDown:");
        SEL longPressSel = NSSelectorFromString(@"performActionsForButtonLongPress:");
        SEL upSel = NSSelectorFromString(@"performActionsForButtonUp:");

        if ([button respondsToSelector:downSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(button, downSel, self.lastDownEvent);
        }
        if ([button respondsToSelector:longPressSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(button, longPressSel, self.lastDownEvent);
        }
        if ([button respondsToSelector:upSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(button, upSel, self.lastDownEvent);
        }
    } @finally {
        ABMCPerformingDefaultAction = NO;
    }
}

#pragma mark - Flashlight (AVFoundation — stable public API)

- (void)toggleFlashlight {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (![device hasTorch]) return;

    NSError *error = nil;
    [device lockForConfiguration:&error];
    if (error) return;

    if (device.torchMode == AVCaptureTorchModeOn) {
        device.torchMode = AVCaptureTorchModeOff;
    } else {
        [device setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
    }
    [device unlockForConfiguration];
}

#pragma mark - Silent Mode

- (void)toggleSilentMode {
    @try {
        id app = [UIApplication sharedApplication];
        SEL rcSel = NSSelectorFromString(@"ringerControl");
        if (![app respondsToSelector:rcSel]) return;

        id ringerControl = ((id (*)(id, SEL))objc_msgSend)(app, rcSel);
        if (!ringerControl) return;

        // Read current muted state — try multiple APIs
        BOOL isMuted = NO;
        BOOL didRead = NO;

        // 1) isRingerMuted (iOS 17)
        SEL isMutedSel = NSSelectorFromString(@"isRingerMuted");
        if ([ringerControl respondsToSelector:isMutedSel]) {
            isMuted = ((BOOL (*)(id, SEL))objc_msgSend)(ringerControl, isMutedSel);
            didRead = YES;
        }

        // 2) _accessibilityIsRingerMuted (iOS 26)
        if (!didRead) {
            SEL accSel = NSSelectorFromString(@"_accessibilityIsRingerMuted");
            if ([ringerControl respondsToSelector:accSel]) {
                isMuted = ((BOOL (*)(id, SEL))objc_msgSend)(ringerControl, accSel);
                didRead = YES;
            }
        }

        // 3) Read _ringerMuted ivar directly as last resort
        if (!didRead) {
            Ivar ivar = class_getInstanceVariable(object_getClass(ringerControl), "_ringerMuted");
            if (ivar) {
                ptrdiff_t offset = ivar_getOffset(ivar);
                isMuted = *(BOOL *)((uint8_t *)(__bridge void *)ringerControl + offset);
                didRead = YES;
            }
        }

        if (!didRead) return;

        // Write new state
        SEL fullSetSel = NSSelectorFromString(@"setRingerMuted:withFeedback:reason:clientType:");
        if ([ringerControl respondsToSelector:fullSetSel]) {
            ((void (*)(id, SEL, BOOL, BOOL, id, unsigned))objc_msgSend)(
                ringerControl, fullSetSel, !isMuted, YES, @"RealActionButton", 0
            );
            return;
        }

        SEL simpleSetSel = NSSelectorFromString(@"setRingerMuted:");
        if ([ringerControl respondsToSelector:simpleSetSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(ringerControl, simpleSetSel, !isMuted);
        }
    } @catch (NSException *e) {
        // Prevent safe mode crash
    }
}

#pragma mark - Screenshot

- (void)takeScreenshot {
    @try {
        id app = [UIApplication sharedApplication];

        SEL managerSel = NSSelectorFromString(@"screenshotManager");
        if ([app respondsToSelector:managerSel]) {
            id manager = ((id (*)(id, SEL))objc_msgSend)(app, managerSel);
            if (manager) {
                SEL saveSel = NSSelectorFromString(@"saveScreenshotsWithCompletion:");
                if ([manager respondsToSelector:saveSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(manager, saveSel, nil);
                    return;
                }
            }
        }

        Class shotterClass = NSClassFromString(@"SBScreenShotter");
        if (shotterClass) {
            SEL sharedSel = NSSelectorFromString(@"sharedInstance");
            if ([shotterClass respondsToSelector:sharedSel]) {
                id instance = ((id (*)(id, SEL))objc_msgSend)(shotterClass, sharedSel);
                SEL saveSel = NSSelectorFromString(@"saveScreenshot");
                if (instance && [instance respondsToSelector:saveSel]) {
                    ((void (*)(id, SEL))objc_msgSend)(instance, saveSel);
                }
            }
        }
    } @catch (NSException *e) {}
}

#pragma mark - Lock Device

- (void)lockDevice {
    @try {
        id app = [UIApplication sharedApplication];
        SEL sel = NSSelectorFromString(@"_simulateLockButtonPress");
        if ([app respondsToSelector:sel]) {
            ((void (*)(id, SEL))objc_msgSend)(app, sel);
        }
    } @catch (NSException *e) {}
}

#pragma mark - Respring

- (void)respring {
    Class fbService = NSClassFromString(@"FBSystemService");
    if (fbService) {
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([fbService respondsToSelector:sharedSel]) {
            id instance = ((id (*)(id, SEL))objc_msgSend)(fbService, sharedSel);
            SEL relaunchSel = NSSelectorFromString(@"exitAndRelaunch:");
            if (instance && [instance respondsToSelector:relaunchSel]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(instance, relaunchSel, YES);
                return;
            }
        }
    }
    exit(0);
}

#pragma mark - Open App

- (void)openApp:(NSString *)bundleID {
    if (!bundleID.length) return;
    @try {
        id application = [UIApplication sharedApplication];
        SEL launchSelector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
        if (application && [application respondsToSelector:launchSelector]) {
            ((BOOL(*)(id,SEL,id,BOOL))objc_msgSend)(application, launchSelector, bundleID, NO);
            ABMCLog(@"Application launched via UIApplication private interface bundle=%@", bundleID);
            return;
        }
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultSelector] ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
        SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (workspace && [workspace respondsToSelector:openSelector]) {
            BOOL opened = ((BOOL(*)(id,SEL,id))objc_msgSend)(workspace, openSelector, bundleID);
            ABMCLog(@"Application launched via LaunchServices bundle=%@ success=%@", bundleID, opened ? @"yes" : @"no");
            return;
        }
        ABMCLog(@"Application launch interface unavailable bundle=%@", bundleID);
    } @catch (NSException *exception) {
        ABMCLog(@"Application launch failed bundle=%@ exception=%@", bundleID, exception.reason ?: @"unknown");
    }
}

- (BOOL)invokeCandidates:(NSArray<NSString *> *)selectors classes:(NSArray<NSString *> *)classes argument:(id)argument {
    for (NSString *className in classes) {
        @try {
            Class cls = NSClassFromString(className);
            if (!cls) continue;
            NSMutableArray *targets = [NSMutableArray arrayWithObject:cls];
            for (NSString *factoryName in @[@"sharedInstance", @"sharedController", @"defaultInstance", @"defaultController"]) {
                SEL factory = NSSelectorFromString(factoryName);
                if ([cls respondsToSelector:factory]) {
                    id target = ((id(*)(id,SEL))objc_msgSend)(cls, factory);
                    if (target) [targets addObject:target];
                }
            }
            for (id target in targets) for (NSString *name in selectors) {
                SEL selector = NSSelectorFromString(name);
                if (![target respondsToSelector:selector]) continue;
                if ([name hasSuffix:@":"]) ((void(*)(id,SEL,id))objc_msgSend)(target, selector, argument);
                else ((void(*)(id,SEL))objc_msgSend)(target, selector);
                ABMCLog(@"System action invoked class=%@ selector=%@", className, name);
                return YES;
            }
        } @catch (NSException *exception) { ABMCLog(@"System target failed class=%@ exception=%@", className, exception.reason ?: @"unknown"); }
    }
    return NO;
}

- (void)performNamedSystemAction:(NSString *)action {
    BOOL ok = NO;
    if ([action isEqualToString:@"controlCenter"]) ok = [self invokeCandidates:@[@"_showControlCenter", @"showControlCenter", @"_presentControlCenter"] classes:@[@"SBUIController", @"SBControlCenterController", @"CCUIOverlayStatusBarPresentationProvider"] argument:nil];
    else if ([action isEqualToString:@"notificationCenter"]) ok = [self invokeCandidates:@[@"_showNotificationCenter", @"showNotificationCenter", @"_revealNotificationCenter"] classes:@[@"SBUIController", @"SBNotificationCenterController", @"SBCoverSheetPresentationManager"] argument:nil];
    else if ([action isEqualToString:@"spotlight"]) ok = [self invokeCandidates:@[@"_activateSpotlight", @"activateSpotlight", @"_showSpotlight"] classes:@[@"SBUIController", @"SBSearchPresentationController", @"SBSpotlightController"] argument:nil];
    else if ([action isEqualToString:@"screenRecord"]) ok = [self invokeCandidates:@[@"_toggleScreenRecording", @"toggleScreenRecording", @"_toggleRecording"] classes:@[@"SBUIController", @"RPControlCenterModule", @"CCUIRecordingModule"] argument:nil];
    else if ([action isEqualToString:@"mediaPlayPause"]) ok = [self invokeCandidates:@[@"togglePlayPause", @"_togglePlayPause"] classes:@[@"SBMediaController", @"MPUNowPlayingController"] argument:nil];
    else if ([action isEqualToString:@"mediaPrevious"]) ok = [self invokeCandidates:@[@"changeTrack:", @"_changeTrack:"] classes:@[@"SBMediaController", @"MPUNowPlayingController"] argument:@(-1)];
    else if ([action isEqualToString:@"mediaNext"]) ok = [self invokeCandidates:@[@"changeTrack:", @"_changeTrack:"] classes:@[@"SBMediaController", @"MPUNowPlayingController"] argument:@(1)];
    else if ([action isEqualToString:@"closeApps"]) ok = [self invokeCandidates:@[@"_dismissSwitcherIfNecessary", @"dismissSwitcher", @"_dismissAppSwitcher"] classes:@[@"SBUIController", @"SBMainSwitcherViewController"] argument:nil];
    ABMCLog(@"System action result action=%@ success=%@", action, ok ? @"yes" : @"no");
}

- (void)invokeSystemAction:(NSString *)selectorName {
    if (!selectorName.length) return;
    @try {
        id app = [UIApplication sharedApplication];
        SEL selector = NSSelectorFromString(selectorName);
        if ([app respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(app, selector);
        }
    } @catch (NSException *exception) {
        // Private system actions are optional and must fail safely.
    }
}

- (void)invokeMediaSelector:(NSString *)selectorName {
    [self invokeMediaSelector:selectorName argument:nil];
}

- (void)invokeMediaSelector:(NSString *)selectorName argument:(id)argument {
    if (!selectorName.length) return;
    @try {
        id app = [UIApplication sharedApplication];
        SEL selector = NSSelectorFromString(selectorName);
        if ([app respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(app, selector, argument);
        }
    } @catch (NSException *exception) {
        // Media controls are optional on some iOS builds.
    }
}

#pragma mark - Open URL

- (void)openURLString:(NSString *)urlString {
    if (!urlString.length) return;

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || !url.scheme.length) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            id app = [UIApplication sharedApplication];
            SEL openSel = NSSelectorFromString(@"openURL:options:completionHandler:");
            if ([app respondsToSelector:openSel]) {
                ((void (*)(id, SEL, id, id, id))objc_msgSend)(app, openSel, url, @{}, nil);
            }
        } @catch (NSException *exception) {
            // A malformed or unsupported scheme must never affect SpringBoard.
        }
    });
}

- (void)executeAppShortcut:(NSString *)payload {
    NSArray *parts = [payload componentsSeparatedByString:@"|"];
    if (parts.count < 2) return;
    NSString *bundleID = parts[0];
    NSString *type = parts[1];
    NSString *title = parts.count > 2 ? parts[2] : type;
    if (!bundleID.length || !type.length) return;
    @try {
        id item = nil;
        Class itemClass = NSClassFromString(@"UIApplicationShortcutItem");
        SEL initializer = NSSelectorFromString(@"initWithType:localizedTitle:localizedSubtitle:icon:userInfo:");
        if (itemClass && [itemClass instancesRespondToSelector:initializer]) item = ((id(*)(id,SEL,id,id,id,id,id))objc_msgSend)([itemClass alloc], initializer, type, title, nil, nil, nil);
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, NSSelectorFromString(@"defaultWorkspace")) : nil;
        Class configClass = NSClassFromString(@"LSApplicationOpenConfiguration");
        id configuration = configClass ? [[configClass alloc] init] : nil;
        SEL setOptions = NSSelectorFromString(@"setFrontBoardOptions:");
        if (configuration && item && [configuration respondsToSelector:setOptions]) ((void(*)(id,SEL,id))objc_msgSend)(configuration, setOptions, @{ @"UIApplicationLaunchOptionsShortcutItemKey": item, @"_UIApplicationShortcutItem": item });
        SEL configuredOpen = NSSelectorFromString(@"openApplicationWithBundleID:configuration:completionHandler:");
        if (workspace && configuration && [workspace respondsToSelector:configuredOpen]) {
            ((void(*)(id,SEL,id,id,id))objc_msgSend)(workspace, configuredOpen, bundleID, configuration, nil);
            ABMCLog(@"App shortcut launched through LS configuration bundle=%@ type=%@", bundleID, type);
            return;
        }
        Class storeClass = NSClassFromString(@"SBApplicationShortcutStore");
        id store = storeClass && [storeClass respondsToSelector:NSSelectorFromString(@"sharedInstance")] ? ((id(*)(id,SEL))objc_msgSend)(storeClass, NSSelectorFromString(@"sharedInstance")) : nil;
        for (NSString *selectorName in @[@"activateShortcutItem:forBundleIdentifier:", @"executeShortcutItem:forBundleIdentifier:", @"performShortcutItem:forBundleIdentifier:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (store && item && [store respondsToSelector:selector]) { ((void(*)(id,SEL,id,id))objc_msgSend)(store, selector, item, bundleID); ABMCLog(@"App shortcut store request bundle=%@ type=%@ selector=%@", bundleID, type, selectorName); return; }
        }
    } @catch (NSException *exception) { ABMCLog(@"App shortcut launch failed bundle=%@ type=%@ exception=%@", bundleID, type, exception.reason ?: @"unknown"); }
    ABMCLog(@"App shortcut launch configuration unavailable; opening application bundle=%@ type=%@", bundleID, type);
    [self openApp:bundleID];
}

- (void)runShortcutWorkflowIdentifier:(NSString *)payload {
    NSArray *parts = [payload componentsSeparatedByString:@"|"];
    NSString *identifier = parts.firstObject;
    NSString *title = parts.count > 1 ? parts[1] : @"";
    if (!identifier.length) return;
    @try {
        ABMCLoadShortcutsRuntime();
        id shortcut = nil;
        for (NSString *className in @[@"SBSApplicationShortcutItem", @"SBApplicationShortcutItem", @"WFWorkflowShortcutItem"]) {
            Class cls = NSClassFromString(className);
            SEL initializer = NSSelectorFromString(@"initWithWorkflowIdentifier:");
            if (!cls || ![cls instancesRespondToSelector:initializer]) continue;
            shortcut = ((id(*)(id,SEL,id))objc_msgSend)([cls alloc], initializer, identifier);
            if (shortcut) break;
        }
        Class storeClass = NSClassFromString(@"SBApplicationShortcutStore");
        id store = storeClass && [storeClass respondsToSelector:NSSelectorFromString(@"sharedInstance")] ? ((id(*)(id,SEL))objc_msgSend)(storeClass, NSSelectorFromString(@"sharedInstance")) : nil;
        SEL activateSelector = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
        if (shortcut && store && [store respondsToSelector:activateSelector]) {
            ((void(*)(id,SEL,id,id,id))objc_msgSend)(store, activateSelector, shortcut, @"com.apple.shortcuts", nil);
            ABMCLog(@"Shortcut UUID activated through SpringBoard identifier=%@", identifier);
            return;
        }
        for (NSString *selectorName in @[@"activateShortcut:forBundleIdentifier:", @"activateShortcutItem:forBundleIdentifier:", @"executeShortcut:withBundleIdentifier:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (shortcut && store && [store respondsToSelector:selector]) {
                ((void(*)(id,SEL,id,id))objc_msgSend)(store, selector, shortcut, @"com.apple.shortcuts");
                ABMCLog(@"Shortcut UUID activated fallback identifier=%@ selector=%@", identifier, selectorName);
                return;
            }
        }
        ABMCLog(@"Shortcut UUID SpringBoard interface unavailable identifier=%@", identifier);
    } @catch (NSException *exception) {
        ABMCLog(@"Shortcut UUID activation failed identifier=%@ exception=%@", identifier, exception.reason ?: @"unknown");
    }
    if (title.length) ABMCLog(@"Shortcut UUID activation unavailable; no recursive name fallback title=%@", title);
}

- (void)runShortcut:(NSString *)name {
    if (!name.length) return;
    @try {
        ABMCLoadShortcutsRuntime();
        Class databaseClass = NSClassFromString(@"ICDatabase");
        SEL sortedSelector = NSSelectorFromString(@"sortedVisibleWorkflowsByName");
        NSMutableArray *databases = [NSMutableArray array];
        if (databaseClass && [databaseClass respondsToSelector:sortedSelector]) [databases addObject:databaseClass];
        for (NSString *factoryName in @[@"sharedDatabase", @"defaultDatabase", @"database"]) {
            SEL factory = NSSelectorFromString(factoryName);
            if (databaseClass && [databaseClass respondsToSelector:factory]) {
                id database = ((id(*)(id,SEL))objc_msgSend)(databaseClass, factory);
                if (database) [databases addObject:database];
            }
        }
        for (id database in databases) {
            if (![database respondsToSelector:sortedSelector]) continue;
            id workflows = ((id(*)(id,SEL))objc_msgSend)(database, sortedSelector);
            for (id workflow in [workflows conformsToProtocol:@protocol(NSFastEnumeration)] ? workflows : @[]) {
                NSString *workflowName = nil;
                for (NSString *selectorName in @[@"name", @"localizedName", @"displayName", @"title"]) {
                    SEL selector = NSSelectorFromString(selectorName);
                    id value = [workflow respondsToSelector:selector] ? ((id(*)(id,SEL))objc_msgSend)(workflow, selector) : nil;
                    if ([value isKindOfClass:[NSString class]] && [value length]) { workflowName = value; break; }
                }
                if (![workflowName isEqualToString:name]) continue;
                id rawIdentifier = nil;
                for (NSString *selectorName in @[@"workflowIdentifier", @"identifier", @"UUID", @"uuid", @"persistentIdentifier"]) {
                    SEL selector = NSSelectorFromString(selectorName);
                    if ([workflow respondsToSelector:selector]) { rawIdentifier = ((id(*)(id,SEL))objc_msgSend)(workflow, selector); if (rawIdentifier) break; }
                }
                NSString *identifier = [rawIdentifier isKindOfClass:[NSString class]] ? rawIdentifier : [rawIdentifier respondsToSelector:@selector(UUIDString)] ? [rawIdentifier UUIDString] : [rawIdentifier description];
                if (identifier.length) { [self runShortcutWorkflowIdentifier:[NSString stringWithFormat:@"%@|%@", identifier, workflowName]]; return; }
            }
        }
        ABMCLog(@"ICDatabase workflow not found name=%@", name);
    } @catch (NSException *exception) {
        ABMCLog(@"ICDatabase workflow lookup failed name=%@ exception=%@", name, exception.reason ?: @"unknown");
    }
}


@end
