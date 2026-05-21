TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := CleanVCamLocal
CleanVCamLocal_FILES := Tweak.xm VCFrameSource.mm VCSampleBufferTools.mm
CleanVCamLocal_CFLAGS := -fobjc-arc
CleanVCamLocal_FRAMEWORKS := Foundation AVFoundation CoreMedia CoreVideo UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
