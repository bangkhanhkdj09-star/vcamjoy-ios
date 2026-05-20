ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES =

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCamBubble
VCamBubble_FILES = Tweak.xm VCFrameProvider.m
VCamBubble_CFLAGS = -fobjc-arc
VCamBubble_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME = VCamJoy
VCamJoy_FILES = VCamJoyApp/main.m VCamJoyApp/VCAppDelegate.m VCamJoyApp/VCViewController.m
VCamJoy_CFLAGS = -fobjc-arc
VCamJoy_FRAMEWORKS = UIKit WebKit
VCamJoy_RESOURCE_FILES = VCamJoyApp/Info.plist
VCamJoy_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
