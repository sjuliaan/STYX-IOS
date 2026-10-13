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

    // anogs (Tencent TSS) bypass
    BOOL anogsBypassOn;
} StyxConfig_t;

extern StyxConfig_t StyxCfg;

// Menu actions
@interface StyxMenuController : NSObject
+ (void)show;
+ (void)hide;
+ (void)toggle;
@end

// ---------------------------------------------------------------------------
// Shared overlay plumbing
//
// Both the menu and the ESP live in their own UIWindow stacked above the game.
// Two rules make that safe:
//
// 1) TOUCH TRANSPARENCY. A UIWindow is itself a view with
//    userInteractionEnabled == YES, so a tap on empty window space hit-tests
//    to the window itself and is CONSUMED. Setting
//    rootViewController.view.userInteractionEnabled = NO does not change this --
//    it only skips that one subview during traversal. Since the menu window
//    sits at UIWindowLevelAlert + 1, it ate every tap intended for Unity and
//    the game became unplayable. Returning nil from hitTest is the only thing
//    that makes UIKit descend to the next window down.
//
// 2) ORIENTATION. codm's Info.plist is landscape-only with
//    UIRequiresFullScreen. A bare UIViewController reports
//    UIInterfaceOrientationMaskAll and shouldAutorotate = YES, so our windows
//    would advertise "any orientation" to the scene and perturb rotation.
//    StyxRootViewController pins them to landscape and never rotates.
// ---------------------------------------------------------------------------

@interface StyxRootViewController : UIViewController
@end

@interface StyxPassthroughWindow : UIWindow
@end

// ESP overlay. Subclasses StyxPassthroughWindow so it inherits the touch
// pass-through -- at UIWindowLevelAlert it would otherwise sit above the game
// and swallow input whenever ESP is enabled.
@interface StyxOverlayWindow : StyxPassthroughWindow
@end

// Entry points
void StyxInstallAimHook(void);
void StyxStartOverlay(void);
void StyxAnogsInstall(void);