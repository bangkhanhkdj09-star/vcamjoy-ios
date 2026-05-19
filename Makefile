ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = Camera
PREFIX = /var/jb

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCamJoyTweak

VCamJoyTweak_FILES = Tweak.x
VCamJoyTweak_FRAMEWORKS = UIKit AVFoundation CoreVideo CoreMedia CoreGraphics
VCamJoyTweak_CFLAGS = -fobjc-arc
VCamJoyTweak_LDFLAGS = -Wl,-rpath,/var/jb/usr/lib

include $(THEOS_MAKE_PATH)/tweak.mk
