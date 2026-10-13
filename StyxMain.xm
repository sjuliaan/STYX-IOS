// ============================================================================
// STYX-iOS — dylib entry point
//
// The dylib itself is loaded by dyld before the game's first frame (we are an
// LC_LOAD_DYLIB on APMDeviceInfoSupport_dylib), so it is already resident at
// process start. What this file controls is WHEN THE MOD BECOMES ACTIVE:
// nothing is installed and nothing is drawn for the first 5 seconds, so the
// game boots cleanly first.
//
// Measured from process start (this constructor), not from scene-ready.
// ============================================================================
#import <Foundation/Foundation.h>
#import "StyxConfig.h"
#import "StyxAnogs.h"

// Fixed arming delay, seconds since process start. Hardcoded by request.
#define STYX_INJECT_DELAY_SEC 5.0

// anogs.framework is loaded by the app; its load order relative to our injected
// dylib is not guaranteed. Retry on the main queue instead of assuming it is
// already resident. 20 tries x 0.5s = up to 10s.
static void StyxInstallAnogsWithRetry(void) {
    __block int attempts = 0;
    __block void (^tryInstall)(void);
    tryInstall = ^{
        StyxAnogsInstall();
        if (StyxAnogs.installed) return;
        if (++attempts >= 20) {
            NSLog(@"[STYX] anogs image never appeared after %d attempts", attempts);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), tryInstall);
    };
    tryInstall();
}

// Everything the mod does happens here, 5s after launch.
static void StyxArmMod(void) {
    // 1) aim-assist amplifier (hook install is idempotent)
    StyxInstallAimHook();

    // 2) begin the periodic writer that drives the real assist-speed field.
    // The hook above is a pass-through; this is what actually changes the
    // assist, because iOS consumes PlayerController+0x1C8 rather than the
    // GetAssitAimSpeed return value.
    StyxAimStart();

    // 3) anogs bypass (retry until the framework is mapped)
    StyxInstallAnogsWithRetry();

    // 4) show the floating menu button
    [StyxMenuController show];

    // 5) if ESP was left on from a previous session, start drawing
    if (StyxCfg.espOn) StyxStartOverlay();

    NSLog(@"[STYX] mod armed at %.1fs", STYX_INJECT_DELAY_SEC);
}

__attribute__((constructor))
static void StyxInit(void) {
    NSLog(@"[STYX] dylib loaded (inert for %.1fs)", STYX_INJECT_DELAY_SEC);

    // Deliberately inert: no hooks, no menu, no overlay until the delay elapses.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(STYX_INJECT_DELAY_SEC * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        StyxArmMod();
    });
}