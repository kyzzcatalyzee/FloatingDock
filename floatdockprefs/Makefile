TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = floatdockprefs

floatdockprefs_FILES = FDRootListController.m
floatdockprefs_FRAMEWORKS = UIKit QuartzCore
floatdockprefs_PRIVATE_FRAMEWORKS = Preferences
floatdockprefs_INSTALL_PATH = /Library/PreferenceBundles
floatdockprefs_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new

include $(THEOS_MAKE_PATH)/bundle.mk
