TARGET := iphone:clang:latest:15.0
ARCHS := arm64
TWEAK_NAME := StyxMenu
INSTALL_TARGET_PROCESSES := codm
SKIP_INSTALL := 1

include $(THEOS)/makefiles/tweak.mk