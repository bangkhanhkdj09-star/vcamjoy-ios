TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := CleanVCamLocal
CleanVCamLocal_FILES := Tweak.xm VCFrameSource.mm VCSampleBufferTools.mm
CleanVCamLocal_CFLAGS := -fobjc-arc
CleanVCamLocal_FRAMEWORKS := Foundation AVFoundation CoreMedia CoreVideo CoreGraphics ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME := CleanVCamLocalPrefs
CleanVCamLocalPrefs_FILES := prefs/RootListController.mm
CleanVCamLocalPrefs_INSTALL_PATH := /Library/PreferenceBundles
CleanVCamLocalPrefs_FRAMEWORKS := Foundation UIKit Photos
CleanVCamLocalPrefs_PRIVATE_FRAMEWORKS := Preferences
CleanVCamLocalPrefs_CFLAGS := -fobjc-arc
CleanVCamLocalPrefs_RESOURCE_DIRS := prefs/Resources

include $(THEOS_MAKE_PATH)/preference_bundle.mk

APPLICATION_NAME := CleanVCam
CleanVCam_FILES := app/main.mm app/AppDelegate.mm app/VCAppViewController.mm
CleanVCam_FRAMEWORKS := Foundation UIKit Photos AVFoundation
CleanVCam_CFLAGS := -fobjc-arc
CleanVCam_INFOPLIST_FILE := app/Resources/Info.plist
CleanVCam_RESOURCE_FILES := app/Resources/Info.plist

include $(THEOS_MAKE_PATH)/application.mk
