TARGET := iphone:clang:$(SDK_VERSION):15.0
INSTALL_TARGET_PROCESSES = Preferences
THEOS_PACKAGE_SCHEME = $(PACKAGE_VARIANT)
export ARCHS = arm64e

BUNDLE_NAME = RealActionButton
$(BUNDLE_NAME)_FILES = ABMCPreferences.m ABMCActionListController.m ABMCLinkEditorController.m ../ABMCLogger.m
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc -I..
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_LIBRARIES = sqlite3
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
