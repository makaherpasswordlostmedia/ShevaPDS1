# ImlacPDS1 — 32-bit iOS 9.3 (armv7) Theos application
TARGET := iphone:clang:9.3:9.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ImlacPDS1

ImlacPDS1_FILES = \
	ImlacPDS1/SourcesObjC/AppDelegate.m \
	ImlacPDS1/SourcesObjC/Machine.m \
	ImlacPDS1/SourcesObjC/Demos.m \
	ImlacPDS1/SourcesObjC/CrtView.m \
	ImlacPDS1/SourcesObjC/MazeWarGame.m \
	ImlacPDS1/SourcesObjC/NetSession.m \
	ImlacPDS1/SourcesObjC/EmulatorViewController.m

ImlacPDS1_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
	-Wno-unknown-warning-option -Wno-nullability-completeness
ImlacPDS1_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
ImlacPDS1_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
