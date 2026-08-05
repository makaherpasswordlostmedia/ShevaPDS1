TARGET := iphone:clang:9.3:9.0
ARCHS = armv7
THEOS_DEVICE_IP =

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ImlacPDS1

ADDITIONAL_CFLAGS += -Wno-unknown-warning-option -Wno-error=unknown-warning-option -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map -Wno-error=nullability-completeness -Wno-nullability-completeness
ADDITIONAL_OBJCFLAGS += -Wno-unknown-warning-option -Wno-error=unknown-warning-option -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map -Wno-error=nullability-completeness -Wno-nullability-completeness
ADDITIONAL_OBJCCFLAGS += -Wno-unknown-warning-option -Wno-error=unknown-warning-option -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map -Wno-error=nullability-completeness -Wno-nullability-completeness

ImlacPDS1_FILES = \
	ImlacPDS1/SourcesObjC/AppDelegate.m \
	ImlacPDS1/SourcesObjC/Machine.m \
	ImlacPDS1/SourcesObjC/Demos.m \
	ImlacPDS1/SourcesObjC/CrtView.m \
	ImlacPDS1/SourcesObjC/MazeWarGame.m \
	ImlacPDS1/SourcesObjC/NetSession.m \
	ImlacPDS1/SourcesObjC/EmulatorViewController.m

ImlacPDS1_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -marm -arch armv7
ImlacPDS1_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
ImlacPDS1_CODESIGN_FLAGS = -Sentitlements.plist
ImlacPDS1_INFOPLIST = Resources/Info.plist

include $(THEOS_MAKE_PATH)/application.mk
