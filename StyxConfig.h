#pragma once
#import <UIKit/UIKit.h>

typedef struct {
    // ESP
    BOOL espOn;
    BOOL espBox;
    BOOL espDistance;
    BOOL espHealth;

    // Aim assist.
    //
    // The slider is 0..100, matching the Android mod's "Locking" slider
    // (Main.cpp: SliderFloat("Locking", &AimAssistSize, 0, 100, "%.0f")).
    // The value is written straight into the game's own assist-speed float
    // fields, so the scale is the game's, not an invented multiplier.
    BOOL  aimOn;
    float aimStrength;

    // anogs (Tencent TSS) bypass
    BOOL anogsBypassOn;
} StyxConfig_t;

extern StyxConfig_t StyxCfg;

// ---------------------------------------------------------------------------
// Runtime status, surfaced in the menu so "is it working?" is a number on
// screen instead of a guess.
// ---------------------------------------------------------------------------

// Aim assist.
typedef struct {
    BOOL  hookInstalled;   // GetAssitAimSpeed pass-through hook landed
    BOOL  haveController;  // GamePlay.get_LocalPC resolved this tick
    BOOL  captured;        // original game value captured at least once
    BOOL  writing;         // we currently own the fields
    float originalValue;   // what the game set
    float writtenValue;    // what we last wrote
    unsigned writes;       // successful field writes
    unsigned restoreCount; // times we put the original back
} StyxAimStats_t;
extern StyxAimStats_t StyxAimStats;

// ESP.
typedef struct {
    BOOL  alive;          // overlay window + view exist
    int   enemiesSeen;    // pawns read from EnemyPawns last frame
    int   enemiesDrawn;   // survivors of the visibility test
    unsigned frames;      // draw attempts
} StyxEspStats_t;
extern StyxEspStats_t StyxEspStats;

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

// The GAME's own window.
//
// A UIWindow created with initWithWindowScene: takes its frame from
// scene.coordinateSpace.bounds, which is FIXED in the device's native
// orientation and does not rotate. On a landscape-only game that is 390x844,
// while the visible area is 844x390 -- so anything positioned from our own
// window's bounds lands in the wrong place (this is why the menu button
// appeared centred against portrait coordinates instead of the landscape
// screen, and why ESP boxes would be misplaced).
//
// The game's window is managed by the scene and its bounds DO track the
// interface orientation, so we attach our views to it instead of running our
// own windows. Touch pass-through is handled by StyxPassthroughContainer's
// hitTest, so game input is still never stolen.
UIWindow *StyxHostWindow(void);

// ESP overlay. A plain container VIEW added to the game's window (see
// StyxHostWindow for why we do not run our own window). Purely visual, so it
// never consumes touches.
@interface StyxOverlayWindow : UIView
@end

// Entry points
void StyxInstallAimHook(void);
void StyxAimStart(void);          // begin the periodic field writer
void StyxAimApplyNow(void);       // force one write (slider changes)
void StyxStartOverlay(void);
void StyxAnogsInstall(void);