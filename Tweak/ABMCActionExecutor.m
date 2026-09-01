#import "ABMCActionExecutor.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define PREFS_DOMAIN CFSTR("com.huynguyen.actionbuttonmulticlick")

BOOL ABMCPerformingDefaultAction = NO;

@interface ABMCActionExecutor ()
- (void)openURLString:(NSString *)urlString;
- (void)openConfiguredURL:(NSString *)urlString;
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
    CFPreferencesAppSynchronize(PREFS_DOMAIN);

    CFStringRef single = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("singleClickAction"), PREFS_DOMAIN);
    CFStringRef dbl = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("doubleClickAction"), PREFS_DOMAIN);
    CFStringRef longPress = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("longPressAction"), PREFS_DOMAIN);

    _singleAction = single ? (__bridge_transfer NSString *)single : @"default";
    _doubleAction = dbl ? (__bridge_transfer NSString *)dbl : @"none";
    _longPressAction = longPress ? (__bridge_transfer NSString *)longPress : @"default";
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
    [self executeAction:action];
}

- (BOOL)usesDefaultLongPressAction {
    return [_longPressAction isEqualToString:@"default"];
}

- (void)executeLongPressAction {
    [self executeAction:_longPressAction];
}

- (void)executeAction:(NSString *)actionID {
    if (!actionID || [actionID isEqualToString:@"none"]) return;

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
        [self invokeSystemAction:@"_showControlCenter"];
    } else if ([actionID isEqualToString:@"notificationCenter"]) {
        [self invokeSystemAction:@"_showNotificationCenter"];
    } else if ([actionID isEqualToString:@"spotlight"]) {
        [self invokeSystemAction:@"_activateSpotlight"];
    } else if ([actionID isEqualToString:@"screenRecord"]) {
        [self invokeSystemAction:@"_toggleScreenRecording"];
    } else if ([actionID isEqualToString:@"mediaPlayPause"]) {
        [self invokeMediaSelector:@"togglePlayPause"];
    } else if ([actionID isEqualToString:@"mediaPrevious"]) {
        [self invokeMediaSelector:@"changeTrack:" argument:@(-1)];
    } else if ([actionID isEqualToString:@"mediaNext"]) {
        [self invokeMediaSelector:@"changeTrack:" argument:@(1)];
    } else if ([actionID isEqualToString:@"closeApps"]) {
        [self invokeSystemAction:@"_dismissSwitcherIfNecessary"];
    } else if ([actionID hasPrefix:@"app:"]) {
        [self openApp:[actionID substringFromIndex:4]];
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
        id app = [UIApplication sharedApplication];

        // SpringBoard-native launch — instant, no LaunchServices overhead
        SEL launchSel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
        if ([app respondsToSelector:launchSel]) {
            ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(app, launchSel, bundleID, NO);
            return;
        }

        // Fallback: LSApplicationWorkspace (async to avoid freeze)
        NSString *bid = [bundleID copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            Class workspace = NSClassFromString(@"LSApplicationWorkspace");
            if (!workspace) return;
            id instance = ((id (*)(id, SEL))objc_msgSend)(workspace, NSSelectorFromString(@"defaultWorkspace"));
            if (!instance) return;
            SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
            if ([instance respondsToSelector:openSel]) {
                ((BOOL (*)(id, SEL, id))objc_msgSend)(instance, openSel, bid);
            }
        });
    } @catch (NSException *e) {}
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

#pragma mark - Run Shortcut

- (void)runShortcut:(NSString *)name {
    if (!name.length) return;

    NSString *encoded = [name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"shortcuts://run-shortcut?name=%@", encoded];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    id app = [UIApplication sharedApplication];
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(app, NSSelectorFromString(@"openURL:options:completionHandler:"), url, @{}, nil);
}

@end
