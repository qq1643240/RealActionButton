TARGET := iphone:clang:$(SDK_VERSION):15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = $(PACKAGE_VARIANT)
export ARCHS = arm64e

TWEAK_NAME = RealActionButton
$(TWEAK_NAME)_FILES = Tweak.x ABMCClickManager.m ABMCActionExecutor.m ../ABMCLogger.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -I..
$(TWEAK_NAME)_FRAMEWORKS = UIKit AudioToolbox AVFoundation

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
