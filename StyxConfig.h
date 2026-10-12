#pragma once
#import <UIKit/UIKit.h>

typedef struct {
    // ESP
    BOOL espOn;
    BOOL espBox;
    BOOL espDistance;
    BOOL espHealth;

    // Aim assist (amplifies the game's own assist speed)
    BOOL  aimOn;
    float aimStrength;   // 1.0 .. 20.0, returned from GetAssitAimSpeed
} StyxConfig_t;

extern StyxConfig_t StyxCfg;

// Menu actions
@interface StyxMenuController : NSObject
+ (void)show;
+ (void)hide;
+ (void)toggle;
@end

// ESP overlay
@interface StyxOverlayWindow : UIWindow
@end

// Entry points
void StyxInstallAimHook(void);
void StyxStartOverlay(void);