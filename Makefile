# ImlacPDS1 — 32-bit iOS 9.3 (armv7) Theos application
TARGET := iphone:clang:9.3:9.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ImlacPDS1

# clang 19 (toolchain) treats the old-style module.map files inside the
# legacy iPhoneOS9.3.sdk as an error (-Wdeprecated-module-dot-map), which
# makes Foundation/UIKit modules fail to build. Silence it, and also build
# without clang modules so SDK module maps are not needed at all.
ImlacPDS1_CFLAGS = -fobjc-arc -fno-modules -fno-implicit-modules \
	-Wno-deprecated-declarations -Wno-unknown-warning-option \
	-Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map \
	-Wno-error=nullability-completeness -Wno-nullability-completeness \
	-Wno-error=unused-command-line-argument -Wno-unused-command-line-argument

ImlacPDS1_FILES = \
	ImlacPDS1/SourcesObjC/AppDelegate.m \
	ImlacPDS1/SourcesObjC/Machine.m \
	ImlacPDS1/SourcesObjC/Demos.m \
	ImlacPDS1/SourcesObjC/CrtView.m \
	ImlacPDS1/SourcesObjC/MazeWarGame.m \
	ImlacPDS1/SourcesObjC/NetSession.m \
	ImlacPDS1/SourcesObjC/EmulatorViewController.m

ImlacPDS1_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
ImlacPDS1_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
