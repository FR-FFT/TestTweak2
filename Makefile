TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak
MyTweak_FILES = Tweak.xm ControllerOverlayView.m Menu.mm Page.mm MenuItem.mm ToggleItem.mm PageItem.mm SliderItem.mm Utils.mm
MyTweak_FRAMEWORKS = UIKit GameController CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
