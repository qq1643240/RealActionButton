#import "ABMCClickManager.h"
#import "ABMCActionExecutor.h"
#import "../ABMCLogger.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL longPressActive = NO;
static BOOL longPressUsedNativeFlow = NO;

static void disableArbiterMultiClick(id buttonInstance) {
    Ivar arbiterIvar = class_getInstanceVariable(object_getClass(buttonInstance), "_buttonArbiter");
    if (!arbiterIvar) return;
    id arbiter = object_getIvar(buttonInstance, arbiterIvar);
    if (!arbiter) return;

    SEL setMaxSel = NSSelectorFromString(@"setMaximumRepeatedPressCount:");
    if ([arbiter respondsToSelector:setMaxSel]) {
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(arbiter, setMaxSel, 0);
    }
}

static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ABMCLog(@"SpringBoard received preferences change notification");
    ABMCActionExecutor *executor = [ABMCActionExecutor sharedExecutor];
    [executor reloadPreferences];
    CFPropertyListRef rawTest = CFPreferencesCopyValue(CFSTR("testAction"), CFSTR("com.huynguyen.actionbuttonmulticlick"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *testAction = rawTest ? (__bridge_transfer NSString *)rawTest : nil;
    if (testAction.length) {
        CFPreferencesSetValue(CFSTR("testAction"), NULL, CFSTR("com.huynguyen.actionbuttonmulticlick"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(CFSTR("com.huynguyen.actionbuttonmulticlick"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        ABMCLog(@"SpringBoard executing requested settings test action=%@", testAction);
        [executor executeAction:testAction];
    }
}

// iOS 26+
%hook SBActionHardwareButton

- (void)_configureButtonArbiter {
    %orig;
    disableArbiterMultiClick(self);
}

- (void)performActionsForButtonDown:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
}

- (void)performActionsForButtonUp:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        BOOL usedNativeFlow = longPressUsedNativeFlow;
        longPressActive = NO;
        longPressUsedNativeFlow = NO;
        if (usedNativeFlow) {
            %orig;
        }
        return;
    }

    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];

    ABMCActionExecutor *executor = [ABMCActionExecutor sharedExecutor];
    if ([executor usesDefaultLongPressAction]) {
        // Preserve the repository's native long-press replay exactly for System Default.
        longPressUsedNativeFlow = YES;
        ABMCPerformingDefaultAction = YES;
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(performActionsForButtonDown:), executor.lastDownEvent);
        %orig;
        ABMCPerformingDefaultAction = NO;
    } else {
        // Custom long press fires at the system's long-press event and never enters native action handling.
        longPressUsedNativeFlow = NO;
        [executor executeLongPressAction];
    }
}

%end

// iOS 17-18
%hook SBRingerHardwareButton

- (void)_configureButtonArbiter {
    %orig;
    disableArbiterMultiClick(self);
}

- (void)performActionsForButtonDown:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
}

- (void)performActionsForButtonUp:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        BOOL usedNativeFlow = longPressUsedNativeFlow;
        longPressActive = NO;
        longPressUsedNativeFlow = NO;
        if (usedNativeFlow) {
            %orig;
        }
        return;
    }

    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];

    ABMCActionExecutor *executor = [ABMCActionExecutor sharedExecutor];
    if ([executor usesDefaultLongPressAction]) {
        // Preserve the repository's native long-press replay exactly for System Default.
        longPressUsedNativeFlow = YES;
        ABMCPerformingDefaultAction = YES;
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(performActionsForButtonDown:), executor.lastDownEvent);
        %orig;
        ABMCPerformingDefaultAction = NO;
    } else {
        // Custom long press fires at the system's long-press event and never enters native action handling.
        longPressUsedNativeFlow = NO;
        [executor executeLongPressAction];
    }
}

%end

%ctor {
    [ABMCClickManager sharedManager].clickCallback = ^(ABMCClickType clickType) {
        [[ABMCActionExecutor sharedExecutor] executeActionForClickType:clickType];
    };

    prefsChanged(NULL, NULL, NULL, NULL, NULL);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        prefsChanged,
        CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
