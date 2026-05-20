THEOS_DEVICE_IP = 127.0.0.1
THEOS_DEVICE_PORT = 2222

# Chi dinh ro arm64 only - iOS 16 khong co armv7
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak
MyTweak_FILES = Tweak.x
MyTweak_CFLAGS = -fobjc-arc
MyTweak_FRAMEWORKS = UIKit Foundation

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS_MAKE_PATH)/tweak.mk
