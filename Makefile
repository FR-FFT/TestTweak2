TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak
MyTweak_FILES = Tweak.xm ControllerOverlayView.m Menu.m Page.m MenuItem.m ToggleItem.m PageItem.m SliderItem.m Utils.m
MyTweak_FRAMEWORKS = UIKit GameController CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
