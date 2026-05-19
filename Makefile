ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

# ── Tweak ────────────────────────────────────────────
TWEAK_NAME = VCamJoyTweak
VCamJoyTweak_FILES = Tweak.x
VCamJoyTweak_FRAMEWORKS = UIKit AVFoundation CoreVideo CoreMedia CoreGraphics CoreImage
VCamJoyTweak_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/tweak.mk

# ── App ──────────────────────────────────────────────
APPLICATION_NAME = VCamJoy
VCamJoy_FILES = VCamJoy/Sources/main.m \
                VCamJoy/Sources/AppDelegate.m \
                VCamJoy/Sources/MainViewController.m
VCamJoy_FRAMEWORKS = UIKit AVFoundation
VCamJoy_CFLAGS = -fobjc-arc
VCamJoy_CODESIGN_FLAGS = -Sentitlements.plist
VCamJoy_INFO_PLIST = VCamJoy/Sources/Info.plist
include $(THEOS_MAKE_PATH)/application.mk
