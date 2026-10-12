// ============================================================================
// STYX-iOS — dylib entry point
// Constructor runs at load time (before the game's UI is up), so everything
// is dispatched to the main thread and retried until the scene exists.
// ============================================================================
#import <Foundation/Foundation.h>
#import "StyxConfig.h"

__attribute__((constructor))
static void StyxInit(void) {
    NSLog(@"[STYX] dylib loaded");

    dispatch_async(dispatch_get_main_queue(), ^{
        // 1) aim-assist amplifier (hook install is idempotent)
        StyxInstallAimHook();

        // 2) show the floating menu button
        [StyxMenuController show];

        // 4) if ESP was left on from a previous session, start drawing
        if (StyxCfg.espOn) StyxStartOverlay();
    });
}