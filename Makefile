.DEFAULT_GOAL := package

PACKAGE_VARIANT ?= roothide
SDK_VERSION ?= 16.5
SUPPORTED_PACKAGE_VARIANTS := rootless roothide

ifeq ($(filter $(PACKAGE_VARIANT),$(SUPPORTED_PACKAGE_VARIANTS)),)
$(error Unsupported PACKAGE_VARIANT '$(PACKAGE_VARIANT)'; expected rootless or roothide)
endif

ifeq ($(strip $(THEOS)),)
$(error THEOS is not set)
endif

ifeq ($(PACKAGE_VARIANT),roothide)
THEOS_PACKAGE_SCHEME := roothide
PACKAGE_CONTROL_PATH := $(CURDIR)/control.roothide
else
THEOS_PACKAGE_SCHEME := rootless
PACKAGE_CONTROL_PATH := $(CURDIR)/control.rootless
endif

export PACKAGE_VARIANT
export SDK_VERSION
export THEOS_PACKAGE_SCHEME
export ARCHS := arm64e
export TARGET := iphone:clang:$(SDK_VERSION):15.0
export _THEOS_DEB_PACKAGE_CONTROL_PATH := $(PACKAGE_CONTROL_PATH)

INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak
SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/aggregate.mk
