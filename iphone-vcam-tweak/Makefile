ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCamBubble
VCamBubble_FILES = Tweak.xm VCBubbleController.m VCFrameProvider.m
VCamBubble_CFLAGS = -fobjc-arc
VCamBubble_FRAMEWORKS = UIKit AVFoundation WebKit CoreMedia CoreVideo

include $(THEOS_MAKE_PATH)/tweak.mk
