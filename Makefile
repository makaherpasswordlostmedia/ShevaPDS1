# ImlacPDS1 — 32-bit iOS 9.3 (armv7) Theos application
TARGET := iphone:clang:9.3:9.0
ARCHS = armv7

# Theos' default Prefix.pch @imports SDK modules (Darwin/Foundation/UIKit).
# Turning modules off breaks the pch ("module 'Darwin' is needed but has not
# been provided"), so keep modules ON and just stop clang 19 from treating
# the legacy module.map files in iPhoneOS9.3.sdk as fatal errors.
export ADDITIONAL_OBJCFLAGS += -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ImlacPDS1

ImlacPDS1_CFLAGS = -fobjc-arc \
	-Wno-deprecated-declarations -Wno-unknown-warning-option \
	-Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map \
	-Wno-error=nullability-completeness -Wno-nullability-completeness \
	-Wno-error=unused-command-line-argument -Wno-unused-command-line-argument \
	-Wno-error=incomplete-umbrella -Wno-incomplete-umbrella \
	-Wno-error=non-modular-include-in-framework-module \
	-Wno-non-modular-include-in-framework-module \
	-Wno-error=non-modular-include-in-module -Wno-non-modular-include-in-module

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
