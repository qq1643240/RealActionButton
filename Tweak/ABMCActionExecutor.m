#import "ABMCActionExecutor.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <SpringBoardServices/SpringBoardServices.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../ABMCLogger.h"

#define PREFS_DOMAIN CFSTR("com.huynguyen.actionbuttonmulticlick")

static CFPropertyListRef ABMCReadPreference(CFStringRef key) {
    return CFPreferencesCopyValue(key, PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

BOOL ABMCPerformingDefaultAction = NO;

@interface ABMCActionExecutor ()
- (void)openURLString:(NSString *)urlString;
- (void)openConfiguredURL:(NSString *)urlString;
- (void)executeAppShortcut:(NSString *)payload;
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
    } else if ([actionID hasPrefix:@"shortcut:"]) {
        [self runShortcut:[actionID substringFromIndex:9]];
    } else if ([actionID hasPrefix:@"url:"]) {
        [self openURLString:[actionID substringFromIndex:4]];
    } else if ([actionID hasPrefix:@"customURL:"]) {
        [self openConfiguredURL:[actionID substringFromIndex:10]];
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
        SBSLaunchApplicationWithIdentifier((__bridge CFStringRef)bundleID, false);
        ABMCLog(@"Application launched via SpringBoardServices bundle=%@", bundleID);
    } @catch (NSException *exception) {
        ABMCLog(@"SpringBoardServices launch failed bundle=%@ exception=%@", bundleID, exception.reason ?: @"unknown");
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

- (void)openConfiguredURL:(NSString *)urlString {
    if (!urlString.length) return;
    NSString *clipboard = [UIPasteboard generalPasteboard].string ?: @"";
    BOOL needsClipboardInput = [urlString containsString:@"$$$"] && !clipboard.length;
    BOOL needsKeywordInput = [urlString containsString:@"@@@"];
    if (!needsClipboardInput && !needsKeywordInput) {
        NSString *resolved = [urlString stringByReplacingOccurrencesOfString:@"$$$" withString:clipboard];
        [self openURLString:resolved];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网址" message:needsKeywordInput ? @"请输入关键词" : @"剪贴板为空，请输入内容" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.keyboardType = UIKeyboardTypeDefault;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"打开" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *value = alert.textFields.firstObject.text ?: @"";
            if (!value.length) return;
            NSString *resolved = [urlString stringByReplacingOccurrencesOfString:@"@@@" withString:value];
            NSString *replacement = needsClipboardInput ? value : ([UIPasteboard generalPasteboard].string ?: @"");
            resolved = [resolved stringByReplacingOccurrencesOfString:@"$$$" withString:replacement];
            [self openURLString:resolved];
        }]];
        UIViewController *presenter = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    presenter = window.rootViewController;
                    break;
                }
            }
            if (presenter) break;
        }
        if (!presenter) return;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

- (void)executeAppShortcut:(NSString *)payload {
    NSArray *parts = [payload componentsSeparatedByString:@"|"];
    if (parts.count < 2) return;
    NSString *bundleID = parts[0];
    NSString *type = parts[1];
    if (!bundleID.length || !type.length) return;
    @try {
        Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
        id item = nil;
        SEL initSel = NSSelectorFromString(@"initWithType:localizedTitle:localizedSubtitle:icon:userInfo:");
        if (itemClass && [itemClass instancesRespondToSelector:initSel]) {
            NSString *title = parts.count > 2 ? parts[2] : type;
            item = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)([itemClass alloc], initSel, type, title, nil, nil, nil);
        }
        Class storeClass = NSClassFromString(@"SBApplicationShortcutStore");
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        id store = storeClass && [storeClass respondsToSelector:sharedSel] ? ((id (*)(id, SEL))objc_msgSend)(storeClass, sharedSel) : nil;
        for (NSString *name in @[@"activateShortcutItem:forBundleIdentifier:", @"activateShortcutItem:forApplication:"]) {
            SEL selector = NSSelectorFromString(name);
            if (item && store && [store respondsToSelector:selector]) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(store, selector, item, bundleID);
                return;
            }
        }
    } @catch (NSException *exception) {}
    [self openApp:bundleID];
}

#pragma mark - Run Shortcut

- (void)runShortcut:(NSString *)name {
    if (!name.length) return;
    @try {
        dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY);
        for (NSString *className in @[@"WFWorkflowRunnerClient", @"WFWorkflowRunner", @"WFWorkflowExecutionService"]) {
            Class cls = NSClassFromString(className);
            if (!cls) continue;
            NSMutableArray *targets = [NSMutableArray arrayWithObject:cls];
            for (NSString *factoryName in @[@"sharedInstance", @"sharedClient", @"defaultClient", @"defaultRunner"]) {
                SEL factory = NSSelectorFromString(factoryName);
                if (![cls respondsToSelector:factory]) continue;
                id target = ((id(*)(id,SEL))objc_msgSend)(cls, factory);
                if (target) [targets addObject:target];
            }
            for (id target in targets) for (NSString *selectorName in @[@"runWorkflowWithName:", @"runShortcutWithName:", @"executeWorkflowNamed:", @"runWorkflowNamed:"]) {
                SEL selector = NSSelectorFromString(selectorName);
                if (![target respondsToSelector:selector]) continue;
                ((void(*)(id,SEL,id))objc_msgSend)(target, selector, name);
                ABMCLog(@"Shortcut background run requested class=%@ selector=%@ name=%@", className, selectorName, name);
                return;
            }
        }
        ABMCLog(@"Shortcut background runner unavailable name=%@", name);
    } @catch (NSException *exception) {
        ABMCLog(@"Shortcut background run failed name=%@ exception=%@", name, exception.reason ?: @"unknown");
    }
}

@end
