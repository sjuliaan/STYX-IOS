// ============================================================================
// STYX-iOS — dylib entry point
// Constructor runs at load time (before the game's UI is up), so everything
// is dispatched to the main thread and retried until the scene exists.
// ============================================================================
#import <Foundation/Foundation.h>
#import "StyxConfig.h"
#import "StyxAnogs.h"

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

__attribute__((constructor))
static void StyxInit(void) {
    NSLog(@"[STYX] dylib loaded");

    dispatch_async(dispatch_get_main_queue(), ^{
        // 1) aim-assist amplifier (hook install is idempotent)
        StyxInstallAimHook();

        // 2) anogs bypass (retry until the framework is mapped)
        StyxInstallAnogsWithRetry();

        // 3) show the floating menu button
        [StyxMenuController show];

        // 4) if ESP was left on from a previous session, start drawing
        if (StyxCfg.espOn) StyxStartOverlay();
    });
}