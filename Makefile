TARGET := iphone:clang:latest:15.0
ARCHS := arm64
TWEAK_NAME := StyxMenu
INSTALL_TARGET_PROCESSES := codm
SKIP_INSTALL := 1

export THEOS_MAKE_PATH = $(THEOS)/makefiles

include $(THEOS_MAKE_PATH)/tweak.mk