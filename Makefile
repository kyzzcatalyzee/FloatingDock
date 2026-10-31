TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FloatDock

FloatDock_FILES = Tweak.xm
FloatDock_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new
FloatDock_FRAMEWORKS = UIKit QuartzCore

SUBPROJECTS += floatdockprefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
